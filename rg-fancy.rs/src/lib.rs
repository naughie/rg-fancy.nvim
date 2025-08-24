mod rg;

mod rpc;

use nvim_router::NeovimWriter;
use nvim_router::RpcArgs;
use nvim_router::nvim_rs::{Neovim, Value};

use std::path::Path;
use std::path::PathBuf;

fn search_results<const CONTEXT_LENGTH: usize>(dir: &Path, pattern: &str) -> Value {
    let Some(results) = rg::search_dir::<CONTEXT_LENGTH>(dir, pattern) else {
        return Value::Nil;
    };
    rpc::to_values::<CONTEXT_LENGTH>(results)
}

fn resolve_path(cwd: &str, path: &str) -> PathBuf {
    let cwd: &Path = cwd.as_ref();
    cwd.join(path)
}

#[derive(Clone)]
pub struct NeovimHandler<const CONTEXT_LENGTH: usize>;

impl<W: NeovimWriter, const CONTEXT_LENGTH: usize> nvim_router::NeovimHandler<W>
    for NeovimHandler<CONTEXT_LENGTH>
{
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

            let path = resolve_path(&cwd, &path);

            Ok(search_results::<CONTEXT_LENGTH>(&path, &pattern))
        } else {
            Ok(Value::Nil)
        }
    }
}

pub type NeovimHandler1 = NeovimHandler<1>;
pub type NeovimHandler2 = NeovimHandler<2>;
pub type NeovimHandler3 = NeovimHandler<3>;
pub type NeovimHandler4 = NeovimHandler<4>;
pub type NeovimHandler5 = NeovimHandler<5>;
pub type NeovimHandler6 = NeovimHandler<6>;
pub type NeovimHandler7 = NeovimHandler<7>;
pub type NeovimHandler8 = NeovimHandler<8>;
pub type NeovimHandler9 = NeovimHandler<9>;
pub type NeovimHandler10 = NeovimHandler<10>;
