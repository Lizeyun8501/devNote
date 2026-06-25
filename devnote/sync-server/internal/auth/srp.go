package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"math/big"
)

// SRPParams holds the parameters for SRP-6a using the 2048-bit group from RFC 5054.
type SRPParams struct {
	n *big.Int // Large safe prime (2048-bit)
	g *big.Int // Generator (2)
	k *big.Int // Multiplier: k = H(N || g)
}

// RFC 5054 2048-bit group prime
var rfc5054Prime2048 = func() *big.Int {
	n := new(big.Int)
	n.SetString("AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773BCAF97A43A1927832133C4C5982B7BEA6B0F47DF84E58A6BAE6DFCE7B7CA70EEDB1BDE0BD7BDDD08F1AB5306A27C4E7DED283C0E0C87117138B4EB5A9BFEE441A3C2C7B5E82F02568F18E53B1C60E4FBD1B06701D8CD54F9C9F8ACFD2B04A0B8CBD46A0AAFD3DB2D819A0CF2E5AE1CB8202E45D302687C287057D8C9A0D", 16)
	return n
}()

// NewSRPParams creates default SRP parameters using RFC 5054 2048-bit group.
func NewSRPParams() *SRPParams {
	N := new(big.Int).Set(rfc5054Prime2048)
	g := big.NewInt(2)

	// k = H(N || g)
	h := sha256.New()
	h.Write(N.Bytes())
	h.Write(g.Bytes())
	kBytes := h.Sum(nil)
	k := new(big.Int).SetBytes(kBytes)

	return &SRPParams{
		n: N,
		g: g,
		k: k,
	}
}

// SRPServer holds the server-side SRP authentication state.
type SRPServer struct {
	params *SRPParams
	b      *big.Int // Server's private ephemeral value
	B      *big.Int // Server's public ephemeral value
	v      *big.Int // Verifier stored for the user
	A      *big.Int // Client's public ephemeral value (set during verify)
	K      []byte   // Derived session key (set after successful verify)
}

// NewSRPServer creates a new SRP server instance with the given parameters.
func NewSRPServer(params *SRPParams) *SRPServer {
	return &SRPServer{params: params}
}

// N returns the safe prime N.
func (p *SRPParams) N() *big.Int {
	return p.n
}

// G returns the generator g.
func (p *SRPParams) G() *big.Int {
	return p.g
}

// GenerateSalt creates a cryptographically random 32-byte salt.
func GenerateSalt() ([]byte, error) {
	salt := make([]byte, 32)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("generate salt: %w", err)
	}
	return salt, nil
}

// GenerateVerifier creates an SRP verifier from username, password, and salt.
// x = SHA256(salt || SHA256(username || ":" || password))
// v = g^x mod N
func GenerateVerifier(params *SRPParams, username, password string, salt []byte) ([]byte, error) {
	x := computeX(username, password, salt)
	v := new(big.Int).Exp(params.g, x, params.n)
	return v.Bytes(), nil
}

// computeX calculates the private key x = SHA256(salt || SHA256(username || ":" || password))
func computeX(username, password string, salt []byte) *big.Int {
	// Inner hash: H(username || ":" || password)
	inner := sha256.New()
	inner.Write([]byte(username))
	inner.Write([]byte(":"))
	inner.Write([]byte(password))
	innerHash := inner.Sum(nil)

	// Outer hash: H(salt || innerHash)
	outer := sha256.New()
	outer.Write(salt)
	outer.Write(innerHash)
	xBytes := outer.Sum(nil)

	return new(big.Int).SetBytes(xBytes)
}

// ComputeB calculates the server's public ephemeral value B.
// b = random (private ephemeral)
// B = (k*v + g^b) mod N
func (s *SRPServer) ComputeB(verifierBytes []byte) ([]byte, error) {
	v := new(big.Int).SetBytes(verifierBytes)
	s.v = v

	// Generate random private ephemeral value b
	b, err := rand.Int(rand.Reader, s.params.n)
	if err != nil {
		return nil, fmt.Errorf("generate random b: %w", err)
	}
	s.b = b

	// B = (k*v + g^b) mod N
	gExpB := new(big.Int).Exp(s.params.g, b, s.params.n)
	kv := new(big.Int).Mul(s.params.k, v)
	B := new(big.Int).Add(kv, gExpB)
	B.Mod(B, s.params.n)
	s.B = B

	return B.Bytes(), nil
}

// ProcessClientProof verifies the client's proof M1 and generates the server's proof M2.
// u = H(A || B)
// S = (A * v^u)^b mod N
// K = SHA256(S)
// M1_expected = H(H(N) XOR H(g) || H(username) || salt || A || B || K)
// M2 = H(A || M1 || K)
func (s *SRPServer) ProcessClientProof(username string, salt []byte, ABytes, M1Bytes []byte) ([]byte, error) {
	A := new(big.Int).SetBytes(ABytes)
	s.A = A

	// A must not be zero mod N (prevents forced session key attacks)
	if A.Mod(A, s.params.n).Sign() == 0 {
		return nil, errors.New("invalid client public value A")
	}

	// u = H(A || B)
	u := computeU(A, s.B)

	// S = (A * v^u)^b mod N
	vExpU := new(big.Int).Exp(s.v, u, s.params.n)
	Avu := new(big.Int).Mul(A, vExpU)
	Avu.Mod(Avu, s.params.n)
	S := new(big.Int).Exp(Avu, s.b, s.params.n)

	// K = SHA256(S)
	K := sha256HashInt(S)
	s.K = K

	// Compute expected M1
	expectedM1 := computeM1(s.params, username, salt, A, s.B, K)

	// Compare M1 (constant-time-ish via big.Int comparison)
	if !bytesEqual(expectedM1, M1Bytes) {
		return nil, errors.New("client proof verification failed")
	}

	// M2 = H(A || M1 || K)
	M2 := computeM2(A, M1Bytes, K)

	return M2, nil
}

// GetSessionKey returns the derived session key after successful authentication.
func (s *SRPServer) GetSessionKey() []byte {
	return s.K
}

// ServerState 是 SRP 服务端会话的可序列化状态，用于跨实例共享（如存入 StateStore/Redis）。
// 仅包含 VerifySRP 所需的字段：私有 ephemeral b、公开 ephemeral B、verifier v。
// params 可由 NewSRPParams 重建，A 与 K 在 verify 阶段重新推导，无需持久化。
type ServerState struct {
	B  []byte // 服务端私有 ephemeral b
	Bb []byte // 服务端公开 ephemeral B
	V  []byte // verifier v
}

// ExportState 导出 SRP 服务端会话状态用于序列化存储。
// 调用前需已执行 ComputeB（保证 b/B/v 非空）。
func (s *SRPServer) ExportState() ServerState {
	state := ServerState{}
	if s.b != nil {
		state.B = s.b.Bytes()
	}
	if s.B != nil {
		state.Bb = s.B.Bytes()
	}
	if s.v != nil {
		state.V = s.v.Bytes()
	}
	return state
}

// NewSRPServerFromState 从序列化状态重建 SRP 服务端会话。
// 用于在 VerifySRP 阶段从 StateStore 恢复会话。
func NewSRPServerFromState(params *SRPParams, state ServerState) *SRPServer {
	srv := &SRPServer{params: params}
	if len(state.B) > 0 {
		srv.b = new(big.Int).SetBytes(state.B)
	}
	if len(state.Bb) > 0 {
		srv.B = new(big.Int).SetBytes(state.Bb)
	}
	if len(state.V) > 0 {
		srv.v = new(big.Int).SetBytes(state.V)
	}
	return srv
}

// computeU calculates the scrambling parameter u = SHA256(A || B)
func computeU(A, B *big.Int) *big.Int {
	h := sha256.New()
	h.Write(A.Bytes())
	h.Write(B.Bytes())
	return new(big.Int).SetBytes(h.Sum(nil))
}

// computeM1 calculates M1 = H(H(N) XOR H(g) || H(username) || salt || A || B || K)
func computeM1(params *SRPParams, username string, salt []byte, A, B *big.Int, K []byte) []byte {
	// H(N)
	hN := sha256HashInt(params.n)
	// H(g)
	hg := sha256HashInt(params.g)

	// H(N) XOR H(g)
	hNxorHg := make([]byte, 32)
	for i := 0; i < 32; i++ {
		hNxorHg[i] = hN[i] ^ hg[i]
	}

	// H(username)
	hUsername := sha256HashString(username)

	h := sha256.New()
	h.Write(hNxorHg)
	h.Write(hUsername)
	h.Write(salt)
	h.Write(A.Bytes())
	h.Write(B.Bytes())
	h.Write(K)
	return h.Sum(nil)
}

// computeM2 calculates M2 = H(A || M1 || K)
func computeM2(A *big.Int, M1, K []byte) []byte {
	h := sha256.New()
	h.Write(A.Bytes())
	h.Write(M1)
	h.Write(K)
	return h.Sum(nil)
}

// sha256HashInt returns SHA256 hash of a big.Int's bytes.
func sha256HashInt(n *big.Int) []byte {
	h := sha256.New()
	h.Write(n.Bytes())
	return h.Sum(nil)
}

// sha256HashString returns SHA256 hash of a string.
func sha256HashString(s string) []byte {
	h := sha256.New()
	h.Write([]byte(s))
	return h.Sum(nil)
}

// bytesEqual performs a constant-time byte comparison.
func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := 0; i < len(a); i++ {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}