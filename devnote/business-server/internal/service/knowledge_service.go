// 知识服务 - 知识关系计算与分析
// 借鉴: 思源笔记知识图谱 (https://github.com/siyuan-note/siyuan)
// - 关系发现与计算
// - 知识覆盖度分析
// - 孤立节点检测
// 借鉴: Obsidian Graph View (https://github.com/obsidianmd)
// - 图谱可视化数据结构
package service

import (
	"database/sql"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/devnote/business-server/internal/model"
	"github.com/google/uuid"
)

// KnowledgeService computes knowledge relationships, graph metrics,
// centrality scores, clusters, and suggestions.
type KnowledgeService struct {
	db     *sql.DB
	config KnowledgeConfig
}

// KnowledgeConfig holds tunable parameters for graph algorithms.
type KnowledgeConfig struct {
	PageRankDamping float64
	PageRankIters   int
}

// NewKnowledgeService creates a new KnowledgeService.
func NewKnowledgeService(db *sql.DB, cfg KnowledgeConfig) *KnowledgeService {
	return &KnowledgeService{db: db, config: cfg}
}

// ----------------------------------------------------------------
// Bidirectional links CRUD
// ----------------------------------------------------------------

// CreateRelation creates or updates a knowledge relation between two notes.
func (s *KnowledgeService) CreateRelation(sourceNoteID, targetNoteID, relationType string, weight float64) (*model.KnowledgeRelation, error) {
	if sourceNoteID == targetNoteID {
		return nil, errors.New("self-referencing knowledge relation is not allowed")
	}

	// Check if relation already exists
	var existing model.KnowledgeRelation
	row := s.db.QueryRow(`
		SELECT id, source_note_id, target_note_id, weight, reference_count, relation_type, created_at, updated_at
		FROM knowledge_relation WHERE source_note_id=? AND target_note_id=? AND relation_type=?
	`, sourceNoteID, targetNoteID, relationType)

	err := row.Scan(&existing.ID, &existing.SourceNoteID, &existing.TargetNoteID,
		&existing.Weight, &existing.ReferenceCount, &existing.RelationType,
		&existing.CreatedAt, &existing.UpdatedAt)

	if err == nil {
		// Update existing
		existing.ReferenceCount++
		existing.Weight = weight
		existing.UpdatedAt = time.Now().UTC()
		_, execErr := s.db.Exec(`UPDATE knowledge_relation SET reference_count=?, weight=?, updated_at=? WHERE id=?`,
			existing.ReferenceCount, existing.Weight, existing.UpdatedAt, existing.ID)
		if execErr != nil {
			return nil, fmt.Errorf("update relation: %w", execErr)
		}

		// Also create reverse link if it doesn't exist
		s.ensureBidirectional(sourceNoteID, targetNoteID, relationType, weight)
		return &existing, nil
	}

	if !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("query relation: %w", err)
	}

	// Create new
	rel := &model.KnowledgeRelation{
		ID:             uuid.New().String(),
		SourceNoteID:   sourceNoteID,
		TargetNoteID:   targetNoteID,
		Weight:         weight,
		ReferenceCount: 1,
		RelationType:   relationType,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	_, execErr := s.db.Exec(`
		INSERT INTO knowledge_relation (id, source_note_id, target_note_id, weight, reference_count, relation_type, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	`, rel.ID, rel.SourceNoteID, rel.TargetNoteID, rel.Weight, rel.ReferenceCount, rel.RelationType, rel.CreatedAt, rel.UpdatedAt)
	if execErr != nil {
		return nil, fmt.Errorf("insert relation: %w", execErr)
	}

	// Ensure bidirectional
	s.ensureBidirectional(sourceNoteID, targetNoteID, relationType, weight)
	return rel, nil
}

func (s *KnowledgeService) ensureBidirectional(sourceNoteID, targetNoteID, relationType string, weight float64) {
	var cnt int
	s.db.QueryRow(`SELECT COUNT(*) FROM knowledge_relation WHERE source_note_id=? AND target_note_id=?`, targetNoteID, sourceNoteID).Scan(&cnt)
	if cnt == 0 {
		now := time.Now().UTC()
		s.db.Exec(`
			INSERT INTO knowledge_relation (id, source_note_id, target_note_id, weight, reference_count, relation_type, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		`, uuid.New().String(), targetNoteID, sourceNoteID, weight*0.8, 1, relationType, now, now)
	}
}

// DeleteRelation removes a knowledge relation.
func (s *KnowledgeService) DeleteRelation(id string) error {
	_, err := s.db.Exec(`DELETE FROM knowledge_relation WHERE id=?`, id)
	return err
}

// GetRelations returns all relations for a note.
func (s *KnowledgeService) GetRelations(noteID string) ([]model.KnowledgeRelation, error) {
	rows, err := s.db.Query(`
		SELECT id, source_note_id, target_note_id, weight, reference_count, relation_type, created_at, updated_at
		FROM knowledge_relation WHERE source_note_id=? OR target_note_id=?
		ORDER BY weight DESC
	`, noteID, noteID)
	if err != nil {
		return nil, fmt.Errorf("get relations: %w", err)
	}
	defer rows.Close()

	var rels []model.KnowledgeRelation
	for rows.Next() {
		var r model.KnowledgeRelation
		if err := rows.Scan(&r.ID, &r.SourceNoteID, &r.TargetNoteID, &r.Weight,
			&r.ReferenceCount, &r.RelationType, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan relation: %w", err)
		}
		rels = append(rels, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate relations: %w", err)
	}
	return rels, nil
}

// ----------------------------------------------------------------
// Knowledge graph edges
// ----------------------------------------------------------------

// GraphEdge represents a weighted edge in the knowledge graph.
type GraphEdge struct {
	Source string  `json:"source"`
	Target string  `json:"target"`
	Weight float64 `json:"weight"`
}

// ComputeGraphEdges returns all knowledge-graph edges weighted by reference frequency.
func (s *KnowledgeService) ComputeGraphEdges() ([]GraphEdge, error) {
	rows, err := s.db.Query(`
		SELECT source_note_id, target_note_id, SUM(weight) as total_weight
		FROM knowledge_relation
		GROUP BY source_note_id, target_note_id
		ORDER BY total_weight DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("compute edges: %w", err)
	}
	defer rows.Close()

	var edges []GraphEdge
	for rows.Next() {
		var e GraphEdge
		if err := rows.Scan(&e.Source, &e.Target, &e.Weight); err != nil {
			return nil, fmt.Errorf("scan edge: %w", err)
		}
		edges = append(edges, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate edges: %w", err)
	}
	return edges, nil
}

// ----------------------------------------------------------------
// Centrality metrics
// ----------------------------------------------------------------

// ComputeMetrics calculates comprehensive graph metrics.
func (s *KnowledgeService) ComputeMetrics() (*model.GraphMetrics, error) {
	edges, err := s.ComputeGraphEdges()
	if err != nil {
		return nil, err
	}

	// Collect all nodes
	nodeSet := make(map[string]bool)
	for _, e := range edges {
		nodeSet[e.Source] = true
		nodeSet[e.Target] = true
	}
	nodes := make([]string, 0, len(nodeSet))
	for n := range nodeSet {
		nodes = append(nodes, n)
	}

	totalNodes := len(nodes)
	totalEdges := len(edges)
	density := 0.0
	if totalNodes > 1 {
		density = float64(totalEdges) / float64(totalNodes*(totalNodes-1))
	}

	// Build adjacency
	adj := make(map[string]map[string]float64)
	inDeg := make(map[string]float64)
	outDeg := make(map[string]float64)
	for _, n := range nodes {
		adj[n] = make(map[string]float64)
		inDeg[n] = 0
		outDeg[n] = 0
	}
	for _, e := range edges {
		adj[e.Source][e.Target] = e.Weight
		outDeg[e.Source] += e.Weight
		inDeg[e.Target] += e.Weight
	}

	// Degree centrality
	degreeCentrality := make(map[string]float64)
	for _, n := range nodes {
		degreeCentrality[n] = (inDeg[n] + outDeg[n]) / float64(totalNodes-1+1) // normalize
	}

	// PageRank
	pageRank := s.computePageRank(nodes, adj)

	// Betweenness (Brandes' algorithm)
	betweenness := s.computeBetweenness(nodes, adj)

	// Clusters (simple connected components via BFS)
	clusters := s.findClusters(nodes, adj)

	// Orphans
	orphans := s.FindOrphanNotes()

	avgDegree := 0.0
	if totalNodes > 0 {
		avgDegree = float64(totalEdges) / float64(totalNodes)
	}

	return &model.GraphMetrics{
		TotalNodes:       totalNodes,
		TotalEdges:       totalEdges,
		Density:          density,
		OrphanCount:      len(orphans),
		ClusterCount:     len(clusters),
		AvgDegree:        avgDegree,
		DegreeCentrality: degreeCentrality,
		PageRank:         pageRank,
		Betweenness:      betweenness,
		Clusters:         clusters,
	}, nil
}

func (s *KnowledgeService) computePageRank(nodes []string, adj map[string]map[string]float64) map[string]float64 {
	n := len(nodes)
	if n == 0 {
		return map[string]float64{}
	}

	damping := s.config.PageRankDamping
	if damping <= 0 {
		damping = 0.85
	}
	iters := s.config.PageRankIters
	if iters <= 0 {
		iters = 100
	}

	rank := make(map[string]float64)
	for _, node := range nodes {
		rank[node] = 1.0 / float64(n)
	}

	for i := 0; i < iters; i++ {
		newRank := make(map[string]float64)
		totalLeaked := 0.0

		for _, node := range nodes {
			incoming := 0.0
			for _, src := range nodes {
				if w, ok := adj[src][node]; ok && w > 0 {
					outSum := 0.0
					for _, w2 := range adj[src] {
						outSum += w2
					}
					if outSum > 0 {
						incoming += rank[src] * (w / outSum)
					}
				}
			}
			newRank[node] = (1.0-damping)/float64(n) + damping*incoming
			totalLeaked += newRank[node]
		}

		// Scale to avoid precision drift
		for _, node := range nodes {
			if totalLeaked > 0 {
				newRank[node] /= totalLeaked
			}
		}

		rank = newRank
	}

	return rank
}

func (s *KnowledgeService) computeBetweenness(nodes []string, adj map[string]map[string]float64) map[string]float64 {
	n := len(nodes)
	betweenness := make(map[string]float64)
	for _, node := range nodes {
		betweenness[node] = 0.0
	}
	if n <= 2 {
		return betweenness
	}

	for _, sNode := range nodes {
		stack := []string{}
		pred := make(map[string][]string)
		sigma := make(map[string]float64)
		dist := make(map[string]int)

		for _, v := range nodes {
			pred[v] = []string{}
			sigma[v] = 0.0
			dist[v] = -1
		}
		sigma[sNode] = 1.0
		dist[sNode] = 0

		queue := []string{sNode}
		for len(queue) > 0 {
			v := queue[0]
			queue = queue[1:]
			stack = append(stack, v)
			for neighbor := range adj[v] {
				if dist[neighbor] < 0 {
					dist[neighbor] = dist[v] + 1
					queue = append(queue, neighbor)
				}
				if dist[neighbor] == dist[v]+1 {
					sigma[neighbor] += sigma[v]
					pred[neighbor] = append(pred[neighbor], v)
				}
			}
		}

		delta := make(map[string]float64)
		for _, v := range nodes {
			delta[v] = 0.0
		}

		for i := len(stack) - 1; i >= 0; i-- {
			w := stack[i]
			for _, v := range pred[w] {
				if sigma[v] > 0 {
					delta[v] += (sigma[v] / sigma[w]) * (1.0 + delta[w])
				}
			}
			if w != sNode {
				betweenness[w] += delta[w]
			}
		}
	}

	return betweenness
}

func (s *KnowledgeService) findClusters(nodes []string, adj map[string]map[string]float64) map[string][]string {
	visited := make(map[string]bool)
	clusters := make(map[string][]string)
	clusterIdx := 0

	for _, node := range nodes {
		if visited[node] {
			continue
		}
		// BFS
		comp := []string{}
		queue := []string{node}
		visited[node] = true

		for len(queue) > 0 {
			curr := queue[0]
			queue = queue[1:]
			comp = append(comp, curr)

			for neighbor := range adj[curr] {
				if !visited[neighbor] {
					visited[neighbor] = true
					queue = append(queue, neighbor)
				}
			}
			// Also add reverse neighbors
			for _, src := range nodes {
				if _, ok := adj[src][curr]; ok && !visited[src] {
					visited[src] = true
					queue = append(queue, src)
				}
			}
		}

		clusterKey := fmt.Sprintf("cluster_%d", clusterIdx)
		clusters[clusterKey] = comp
		clusterIdx++
	}

	return clusters
}

// ----------------------------------------------------------------
// Orphan notes
// ----------------------------------------------------------------

// FindOrphanNotes returns note IDs that have no knowledge relations.
func (s *KnowledgeService) FindOrphanNotes() []string {
	rows, err := s.db.Query(`
		SELECT nm.id FROM note_meta nm
		WHERE NOT EXISTS (
			SELECT 1 FROM knowledge_relation kr WHERE kr.source_note_id = nm.id OR kr.target_note_id = nm.id
		)
	`)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var orphans []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			continue
		}
		orphans = append(orphans, id)
	}
	if err := rows.Err(); err != nil {
		return nil
	}
	return orphans
}

// ----------------------------------------------------------------
// Related notes suggestions
// ----------------------------------------------------------------

// SuggestRelatedNotes returns the top N notes related to the given note,
// sorted by a combined score of shared tags, shared folder, and link weight.
func (s *KnowledgeService) SuggestRelatedNotes(noteID string, limit int) ([]SuggestedNote, error) {
	if limit < 1 {
		limit = 10
	}

	// Collect candidate notes via shared tags
	tagRows, err := s.db.Query(`
		SELECT DISTINCT tr2.note_id FROM tag_relation tr1
		INNER JOIN tag_relation tr2 ON tr1.tag_id = tr2.tag_id AND tr1.note_id != tr2.note_id
		WHERE tr1.note_id = ?
	`, noteID)
	if err != nil {
		return nil, fmt.Errorf("tag candidates: %w", err)
	}
	defer tagRows.Close()

	candidateScores := make(map[string]float64)
	for tagRows.Next() {
		var candidateID string
		if err := tagRows.Scan(&candidateID); err != nil {
			continue
		}
		candidateScores[candidateID] += 3.0 // tag match weight
	}
	if err := tagRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate tag rows: %w", err)
	}

	// Collect via knowledge relations
	relRows, err := s.db.Query(`
		SELECT target_note_id, weight FROM knowledge_relation WHERE source_note_id = ?
		UNION
		SELECT source_note_id, weight FROM knowledge_relation WHERE target_note_id = ?
	`, noteID, noteID)
	if err != nil {
		return nil, fmt.Errorf("rel candidates: %w", err)
	}
	defer relRows.Close()

	for relRows.Next() {
		var candidateID string
		var weight float64
		if err := relRows.Scan(&candidateID, &weight); err != nil {
			continue
		}
		candidateScores[candidateID] += weight * 2.0
	}
	if err := relRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rel rows: %w", err)
	}

	// Sort by score
	type scorePair struct {
		id    string
		score float64
	}
	var pairs []scorePair
	for id, score := range candidateScores {
		pairs = append(pairs, scorePair{id: id, score: score})
	}
	sort.Slice(pairs, func(i, j int) bool {
		return pairs[i].score > pairs[j].score
	})

	if len(pairs) > limit {
		pairs = pairs[:limit]
	}

	var suggestions []SuggestedNote
	for _, p := range pairs {
		title, _ := s.getNoteTitle(p.id)
		suggestions = append(suggestions, SuggestedNote{
			NoteID: p.id,
			Title:  title,
			Score:  p.score,
		})
	}
	return suggestions, nil
}

// SuggestedNote represents a note recommendation.
type SuggestedNote struct {
	NoteID string  `json:"note_id"`
	Title  string  `json:"title"`
	Score  float64 `json:"score"`
}

func (s *KnowledgeService) getNoteTitle(noteID string) (string, error) {
	var title string
	err := s.db.QueryRow(`SELECT title FROM note_meta WHERE id=?`, noteID).Scan(&title)
	return title, err
}

// ----------------------------------------------------------------
// Knowledge coverage metrics
// ----------------------------------------------------------------

// CoverageMetrics quantifies how well notes are linked.
type CoverageMetrics struct {
	TotalNotes       int     `json:"total_notes"`
	LinkedNotes      int     `json:"linked_notes"`
	OrphanNotes      int     `json:"orphan_notes"`
	CoveragePercent  float64 `json:"coverage_percent"`
	AvgLinksPerNote  float64 `json:"avg_links_per_note"`
	TotalLinks       int     `json:"total_links"`
	MaxLinksOnNote   int     `json:"max_links_on_note"`
	NoteWithMaxLinks string  `json:"note_with_max_links"`
}

// ComputeCoverage computes knowledge coverage metrics.
func (s *KnowledgeService) ComputeCoverage() (*CoverageMetrics, error) {
	var totalNotes int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM note_meta`).Scan(&totalNotes); err != nil {
		return nil, fmt.Errorf("count notes: %w", err)
	}

	orphans := s.FindOrphanNotes()
	orphanCount := len(orphans)

	var totalLinks int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM knowledge_relation`).Scan(&totalLinks); err != nil {
		return nil, fmt.Errorf("count relations: %w", err)
	}

	linkedNotes := totalNotes - orphanCount

	coveragePercent := 0.0
	if totalNotes > 0 {
		coveragePercent = float64(linkedNotes) / float64(totalNotes) * 100
	}

	avgLinks := 0.0
	if totalNotes > 0 {
		avgLinks = float64(totalLinks) / float64(totalNotes)
	}

	// Find note with max links
	rows, err := s.db.Query(`
		SELECT note_id, COUNT(*) as cnt FROM (
			SELECT source_note_id as note_id FROM knowledge_relation
			UNION ALL
			SELECT target_note_id as note_id FROM knowledge_relation
		) GROUP BY note_id ORDER BY cnt DESC LIMIT 1
	`)
	maxLinks := 0
	maxNote := ""
	if err == nil {
		defer rows.Close()
		if rows.Next() {
			rows.Scan(&maxNote, &maxLinks)
		}
		if err := rows.Err(); err != nil {
			return nil, fmt.Errorf("iterate coverage rows: %w", err)
		}
	}

	return &CoverageMetrics{
		TotalNotes:       totalNotes,
		LinkedNotes:      linkedNotes,
		OrphanNotes:      orphanCount,
		CoveragePercent:  math.Round(coveragePercent*100) / 100,
		AvgLinksPerNote:  math.Round(avgLinks*100) / 100,
		TotalLinks:       totalLinks,
		MaxLinksOnNote:   maxLinks,
		NoteWithMaxLinks: maxNote,
	}, nil
}

// ----------------------------------------------------------------
// Utility
// ----------------------------------------------------------------

// FindShortestPath computes the shortest path (by weight) between two notes using Dijkstra.
func (s *KnowledgeService) FindShortestPath(fromNoteID, toNoteID string) ([]string, float64, error) {
	edges, err := s.ComputeGraphEdges()
	if err != nil {
		return nil, 0, err
	}

	// Build adjacency
	adj := make(map[string]map[string]float64)
	for _, e := range edges {
		if adj[e.Source] == nil {
			adj[e.Source] = make(map[string]float64)
		}
		adj[e.Source][e.Target] = e.Weight
	}

	// Dijkstra
	dist := make(map[string]float64)
	prev := make(map[string]string)
	visited := make(map[string]bool)

	dist[fromNoteID] = 0

	for {
		u := ""
		minDist := math.MaxFloat64
		for node, d := range dist {
			if !visited[node] && d < minDist {
				u = node
				minDist = d
			}
		}
		if u == "" || u == toNoteID {
			break
		}
		visited[u] = true

		for v, w := range adj[u] {
			alt := dist[u] + (1.0 / (w + 0.001)) // inverse weight for shortest path
			if current, ok := dist[v]; !ok || alt < current {
				dist[v] = alt
				prev[v] = u
			}
		}
	}

	if _, ok := dist[toNoteID]; !ok {
		return nil, 0, fmt.Errorf("no path found between %s and %s", fromNoteID, toNoteID)
	}

	// Reconstruct path
	var path []string
	for at := toNoteID; at != ""; at = prev[at] {
		path = append([]string{at}, path...)
		if at == fromNoteID {
			break
		}
	}

	return path, dist[toNoteID], nil
}

// findSimilarNotesByContent returns notes with similar titles (simple string similarity).
func (s *KnowledgeService) findSimilarNotesByContent(noteID string, limit int) ([]SuggestedNote, error) {
	var myTitle string
	if err := s.db.QueryRow(`SELECT title FROM note_meta WHERE id=?`, noteID).Scan(&myTitle); err != nil {
		return nil, err
	}

	rows, err := s.db.Query(`SELECT id, title FROM note_meta WHERE id != ?`, noteID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type candidate struct {
		id    string
		title string
		sim   float64
	}
	var candidates []candidate
	for rows.Next() {
		var id, title string
		if err := rows.Scan(&id, &title); err != nil {
			continue
		}
		sim := jaccardSimilarity(strings.ToLower(myTitle), strings.ToLower(title))
		candidates = append(candidates, candidate{id, title, sim})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].sim > candidates[j].sim
	})

	if len(candidates) > limit {
		candidates = candidates[:limit]
	}

	var suggestions []SuggestedNote
	for _, c := range candidates {
		suggestions = append(suggestions, SuggestedNote{
			NoteID: c.id,
			Title:  c.title,
			Score:  c.sim,
		})
	}
	return suggestions, nil
}

func jaccardSimilarity(a, b string) float64 {
	setA := tokenSet(a)
	setB := tokenSet(b)
	if len(setA) == 0 && len(setB) == 0 {
		return 0
	}
	intersection := 0
	for token := range setA {
		if setB[token] {
			intersection++
		}
	}
	union := len(setA) + len(setB) - intersection
	if union == 0 {
		return 0
	}
	return float64(intersection) / float64(union)
}

func tokenSet(s string) map[string]bool {
	words := strings.Fields(s)
	set := make(map[string]bool, len(words))
	for _, w := range words {
		set[w] = true
	}
	return set
}