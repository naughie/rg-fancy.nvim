mod rg;

mod rpc;

use nvim_router::NeovimWriter;
use nvim_router::RpcArgs;
use nvim_router::nvim_rs::{Neovim, Value};

use std::path::Path;
use std::path::PathBuf;

fn search_results(dir: &Path, pattern: &str) -> Value {
    let Some(results) = rg::search_dir(dir, pattern) else {
        return Value::Nil;
    };
    rpc::to_values(results)
}

fn resolve_path(cwd: &str, path: &str) -> Option<PathBuf> {
    let cwd: &Path = cwd.as_ref();
    cwd.join(path).canonicalize().ok()
}

#[derive(Clone)]
pub struct NeovimHandler;

impl<W: NeovimWriter> nvim_router::NeovimHandler<W> for NeovimHandler {
    fn new() -> Self {
        Self
    }

    async fn handle_request(
        &self,
        name: &str,
        mut args: RpcArgs,
        _neovim: Neovim<W>,
    ) -> Result<Value, Value> {
        if name == "grep" {
            let Some(cwd) = args.next_string() else {
                return Ok(Value::Nil);
            };
            let Some(path) = args.next_string() else {
                return Ok(Value::Nil);
            };
            let Some(pattern) = args.next_string() else {
                return Ok(Value::Nil);
            };

            let Some(path) = resolve_path(&cwd, &path) else {
                return Ok(Value::Nil);
            };

            Ok(search_results(&path, &pattern))
        } else {
            Ok(Value::Nil)
        }
    }
}
