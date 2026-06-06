use std::fs;
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Set proto output directory so we can post-process it
    let out_dir = PathBuf::from(std::env::var("OUT_DIR")?);

    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .out_dir(&out_dir)
        .compile_protos(&["../../proto/devnote.proto"], &["../../proto"])?;

    // Post-process: fix Self::Future ambiguity in generated server code
    // In Rust 1.92+, Self::Future is ambiguous when a type implements multiple
    // traits that each have an associated Future type.
    // Fix: replace `-> Self::Future` with `-> <Self as GrpcService<B>>::Future`
    let generated_file = out_dir.join("devnote.rs");
    if generated_file.exists() {
        let content = fs::read_to_string(&generated_file)?;
        let fixed = fix_self_future_ambiguity(&content);
        fs::write(&generated_file, fixed)?;
    }

    Ok(())
}

/// Fix the `Self::Future` ambiguity in tonic-generated server code.
///
/// The generated code has impl blocks like:
/// ```ignore
/// impl<T, B> GrpcService<B> for SomeServiceServer<T> {
///     type Future = BoxFuture<Self::Response, Self::Error>;
///     fn call(&mut self, req: http::Request<B>) -> Self::Future { ... }
/// }
/// ```
/// Where `Self::Future` in the return type of `call` is ambiguous because
/// `SomeServiceServer<T>` implements multiple traits with `Future` associated types.
///
/// We replace `-> Self::Future` in `fn call` with the fully-qualified
/// `<Self as tonic::transport::GrpcService<B>>::Future`.
fn fix_self_future_ambiguity(content: &str) -> String {
    // Strategy: In each `impl<...> GrpcService<B> for ...Server<...>` block,
    // replace `-> Self::Future` in `fn call` with the fully-qualified path.
    //
    // We do a simple text replacement: find lines matching
    // `fn call(&mut self, req: http::Request<B>) -> Self::Future {`
    // and replace `Self::Future` with `<Self as GrpcService<B>>::Future`

    let mut result = String::with_capacity(content.len());
    let mut in_grpc_service_impl = false;
    let mut current_type_params = String::new();

    for line in content.lines() {
        // Detect start of GrpcService impl block
        if line.contains("impl<") && line.contains("> tonic::transport::GrpcService<") {
            in_grpc_service_impl = true;
            // Extract the B type parameter - it's the one used in GrpcService<B>
            // e.g., "impl<T, B> tonic::transport::GrpcService<B> for DevNoteServiceServer<T>"
            if let Some(start) = line.find("GrpcService<") {
                let after = &line[start + "GrpcService<".len()..];
                if let Some(end) = after.find('>') {
                    current_type_params = after[..end].to_string();
                }
            }
            result.push_str(line);
            result.push('\n');
            continue;
        }

        // Detect end of impl block
        if in_grpc_service_impl && line.trim() == "}" && !line.starts_with(' ') && !line.starts_with('\t') {
            in_grpc_service_impl = false;
            current_type_params.clear();
            result.push_str(line);
            result.push('\n');
            continue;
        }

        // Fix Self::Future in fn call within GrpcService impl
        if in_grpc_service_impl && line.contains("fn call(&mut self, req: http::Request<B>) -> Self::Future") {
            let fixed_line = line.replace(
                "-> Self::Future",
                &format!("-> <Self as tonic::transport::GrpcService<{}>>::Future", current_type_params),
            );
            result.push_str(&fixed_line);
            result.push('\n');
            continue;
        }

        result.push_str(line);
        result.push('\n');
    }

    result
}
