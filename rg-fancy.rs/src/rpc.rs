use crate::rg::{RgErr, RgResult, RgResults};

use nvim_router::nvim_rs::Value;

fn err_value(e: RgErr, path: Option<&str>) -> Value {
    let mut inner = vec![(Value::from("error"), Value::from(e.msg))];
    if let Some(path) = path {
        inner.push((Value::from("path"), Value::from(path)));
    }
    Value::Map(inner)
}

fn result_value(result: RgResult, path: &str) -> Value {
    let mut inner = vec![(Value::from("path"), Value::from(path))];

    if let Some(value) = result.line_idx {
        inner.push((Value::from("line_idx"), Value::from(value)));
    }

    inner.push((
        Value::from("before"),
        Value::Array(
            result
                .before
                .map(|line| {
                    if let Some(line) = line {
                        Value::from(line)
                    } else {
                        Value::Nil
                    }
                })
                .to_vec(),
        ),
    ));

    inner.push((
        Value::from("after"),
        Value::Array(
            result
                .after
                .map(|line| {
                    if let Some(line) = line {
                        Value::from(line)
                    } else {
                        Value::Nil
                    }
                })
                .to_vec(),
        ),
    ));

    if let Some(value) = result.matched {
        inner.push((
            Value::from("matched"),
            Value::Array(value.into_iter().map(Value::from).collect()),
        ));
    }

    Value::Map(inner)
}

pub fn to_values(
    search_results: impl Iterator<Item = Result<(RgResults, Option<RgErr>), RgErr>>,
) -> Value {
    let mut rpc_values = Vec::new();

    for result in search_results {
        match result {
            Ok((results, err)) => {
                let (path, results) = results.into_raw();
                for result in results {
                    rpc_values.push(result_value(result, &path));
                }
                if let Some(e) = err {
                    rpc_values.push(err_value(e, Some(&path)));
                }
            }
            Err(e) => rpc_values.push(err_value(e, None)),
        }
    }

    Value::Array(rpc_values)
}
