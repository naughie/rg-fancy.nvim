use grep::regex::{self, RegexMatcher};
use grep::searcher::{Searcher, Sink, SinkContext, SinkMatch};

use std::path::Path;

const CONTEXT_LENGTH: usize = 2;

fn build_walker(path: &Path) -> impl Iterator<Item = Result<ignore::DirEntry, ignore::Error>> {
    use ignore::WalkBuilder;

    let mut builder = WalkBuilder::new(path);

    builder
        .follow_links(true)
        .max_filesize(Some(1_000_000_000))
        .threads(1)
        .hidden(false);
    let mut overrides = ignore::overrides::OverrideBuilder::new(path);
    overrides.add("!**/.git").ok();
    if let Ok(overrides) = overrides.build() {
        builder.overrides(overrides);
    }

    builder.build().filter(|entry| {
        entry
            .as_ref()
            .is_ok_and(|entry| entry.file_type().is_some_and(|ft| ft.is_file()))
    })
}

fn build_matcher(pattern: &str) -> Result<RegexMatcher, regex::Error> {
    use grep::regex::RegexMatcherBuilder;

    let mut builder = RegexMatcherBuilder::new();

    builder
        .case_smart(true)
        // true: ^/$ matches the beginning/end of lines
        // false: ^/$ matches the beginning/end of the input
        .multi_line(true)
        // true: a* greedy, a*? lazy
        // false: a* lazy, a*? greedy
        .swap_greed(true)
        .ignore_whitespace(false)
        .line_terminator(Some(b'\n'))
        .dot_matches_new_line(false);

    builder.build(pattern)
}

fn build_searcher() -> Searcher {
    use grep::searcher::SearcherBuilder;

    let mut builder = SearcherBuilder::new();
    builder
        .after_context(CONTEXT_LENGTH)
        .before_context(CONTEXT_LENGTH)
        .multi_line(true)
        .stop_on_nonmatch(false);

    builder.build()
}

fn path_to_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[derive(Debug, Default)]
pub struct RgResult {
    pub line_idx: Option<u64>,
    pub before: [Option<String>; CONTEXT_LENGTH],
    pub after: [Option<String>; CONTEXT_LENGTH],
    pub matched: Option<Vec<String>>,
}

pub struct RgErr {
    pub msg: String,
}

impl RgErr {
    fn from(e: impl std::error::Error) -> Self {
        Self { msg: e.to_string() }
    }
}

impl RgResult {
    fn update_matched(&mut self, src: &SinkMatch<'_>) {
        self.line_idx = src.line_number();

        let lines = src
            .lines()
            .map(|line| String::from_utf8_lossy(line.trim_ascii_end()).into_owned())
            .collect();
        self.matched = Some(lines);
    }

    fn is_matched(&self) -> bool {
        self.matched.is_some()
    }

    fn is_full_before(&self) -> bool {
        self.before[0].is_some() && self.before[1].is_some()
    }

    fn context(ctx: &SinkContext<'_>) -> String {
        String::from_utf8_lossy(ctx.bytes().trim_ascii_end()).into_owned()
    }

    fn first_matched_line(&self) -> Option<String> {
        self.matched
            .as_ref()
            .and_then(|lines| lines.first().cloned())
    }

    fn second_matched_line(&self) -> Option<String> {
        self.matched
            .as_ref()
            .and_then(|lines| lines.get(2).cloned())
    }

    fn last_matched_line(&self) -> Option<String> {
        self.matched
            .as_ref()
            .and_then(|lines| lines.last().cloned())
    }

    fn second_last_matched_line(&self) -> Option<String> {
        self.matched
            .as_ref()
            .and_then(|lines| lines.iter().rev().nth(1).cloned())
    }
}

#[derive(Debug)]
pub struct RgResults {
    inner: Vec<RgResult>,
    path: String,
}

struct LastResults<'a> {
    last: Option<&'a mut RgResult>,
    second_last: Option<&'a mut RgResult>,
}

impl RgResults {
    fn from_path(path: &Path) -> Self {
        Self {
            inner: Default::default(),
            path: path_to_string(path),
        }
    }

    fn last_two_mut(&mut self) -> LastResults<'_> {
        if let Some((last, rest)) = self.inner.split_last_mut() {
            let second_last = rest.last_mut();
            LastResults {
                last: Some(last),
                second_last,
            }
        } else {
            LastResults {
                last: None,
                second_last: None,
            }
        }
    }

    fn push(&mut self, item: RgResult) {
        self.inner.push(item);
    }

    pub fn into_raw(self) -> (String, Vec<RgResult>) {
        (self.path, self.inner)
    }
}
// # State of [ inner[inner.len() - 2].after, inner[inner.len() - 1].before, inner[inner.len() - 1].after ]
//
// ## Reading a match
//
// ### Break down
//   When reading a match,
//     a) if last.matched is Some, then case (1)/(2)/(3);
//     b) if last.matched is None, then case (4)/(5).
//
//   If a), then
//       if last.after is [None, None] then case (1);
//       if last.after is [Some, None] then case (2);
//       if last.after is [Some, Some] then case (3).
//   If b), then
//       if last.before is [Some, None] then case (4);
//       if last.before is [Some, Some] then case (5) and do nothing.
//
//
// ### 1. No contexts
//
// match 1
// <- [ [None, None], null, null ]
// match 2
// <- [ [Some(match 1), None], [match 1.before, Some(match 1)], [None, None] ]
//
//
// ### 2. One context
//
// match 1
// <- [ [None, None], null, null ]
// context 1
// <- [ [Some(1), None], null, null ]
// match 2
// <- [ [Some(1), Some(match 2)], [Some(match 1), Some(1)], [None, None] ]
//
//
// ### 3. Two contexts
//
// match
// <- [ [None, None], null, null ]
// context 1
// <- [ [Some(1), None], null, null ]
// context 2
// <- [ [Some(1), Some(2)], null, null ]
// match
// <- [ [Some(1), Some(2)], [Some(1), Some(2)], [None, None] ]
//
//
// ### 4. Three contexts
//
// match
// <- [ [None, None], null, null ]
// context 1
// <- [ [Some(1), None], null, null ]
// context 2
// <- [ [Some(1), Some(2)], null, null ]
// context 3
// <- [ [Some(1), Some(2)], [Some(3), None], [None, None] ]
// match
// <- [ [Some(1), Some(2)], [Some(2), Some(3)], [None, None] ]
//
//
// ### 5. Four or more contexts
//
// match
// <- [ [None, None], null, null ]
// context 1
// <- [ [Some(1), None], null, null ]
// context 2
// <- [ [Some(1), Some(2)], null, null ]
// context 3
// <- [ [Some(1), Some(2)], [Some(3), None], [None, None] ]
// context 4
// <- [ [Some(1), Some(2)], [Some(3), Some(4)], [None, None] ]
// match
// <- [ [Some(1), Some(2)], [Some(3), Some(4)], [None, None] ]
//
//
// ## Reading a context
//
//   When reading a context,
//     a) if last.matched is Some, then case (1)/(2)/(3);
//     b) if last.matched is None, then case (4).
//
//   If a), then
//       if last.after is [None, None] then case (1);
//       if last.after is [Some, None] then case (2);
//       if last.after is [Some, Some] then case (3).
//
//
// match
// <- [ [None, None], null, null ]
// context 1
// (1) <- [ [Some(1), None], null, null ]
// context 2
// (2) <- [ [Some(1), Some(2)], null, null ]
// context 3
// (3) <- [ [Some(1), Some(2)], [Some(3), None], [None, None] ]
// context 4
// (4) <- [ [Some(1), Some(2)], [Some(3), Some(4)], [None, None] ]
impl Sink for RgResults {
    type Error = std::io::Error;

    fn matched(&mut self, _searcher: &Searcher, mat: &SinkMatch<'_>) -> Result<bool, Self::Error> {
        let last_two = self.last_two_mut();

        if let Some(last) = last_two.last {
            if last.is_matched() {
                let mut res = RgResult::default();
                res.update_matched(mat);

                if let Some(second_last) = last_two.second_last
                    && second_last.after[1].is_none()
                {
                    second_last.after[1] = res.first_matched_line();
                }

                if last.after[0].is_none() {
                    match (res.first_matched_line(), res.second_matched_line()) {
                        (Some(a), Some(b)) => {
                            last.after[0] = Some(a);
                            last.after[1] = Some(b);
                        }
                        (Some(a), None) => {
                            last.after[0] = Some(a);
                        }
                        _ => {}
                    }

                    match (last.last_matched_line(), last.second_last_matched_line()) {
                        (Some(a), Some(b)) => {
                            res.before[1] = Some(a);
                            res.before[0] = Some(b);
                        }
                        (Some(a), None) => {
                            if let Some(b) = last.before[1].as_ref() {
                                res.before[1] = Some(a);
                                res.before[0] = Some(b.clone());
                            } else if let Some(b) = last.before[0].as_ref() {
                                res.before[1] = Some(a);
                                res.before[0] = Some(b.clone());
                            } else {
                                res.before[0] = Some(a);
                            }
                        }
                        _ => {}
                    }
                } else if last.after[1].is_none() {
                    last.after[1] = res.first_matched_line();
                    res.before[0] = last.last_matched_line();
                    res.before[1] = last.after[0].clone();
                } else {
                    res.before = last.after.clone();
                }

                self.push(res);
            } else if let Some(second_last) = last_two.second_last {
                if !last.is_full_before() {
                    last.before.rotate_right(1);
                    last.before[0] = second_last.after[1].clone();
                }
                last.update_matched(mat);
            } else {
                last.update_matched(mat);
            }
        } else {
            let mut res = RgResult::default();
            res.update_matched(mat);

            self.push(res);
        }

        Ok(true)
    }

    fn context(
        &mut self,
        _searcher: &Searcher,
        context: &SinkContext<'_>,
    ) -> Result<bool, Self::Error> {
        let context = RgResult::context(context);

        let last_two = self.last_two_mut();

        if let Some(last) = last_two.last {
            if let Some(second_last) = last_two.second_last
                && second_last.after[1].is_none()
            {
                second_last.after[1] = Some(context.clone());
            }

            if last.is_matched() {
                if last.after[0].is_none() {
                    last.after[0] = Some(context);
                } else if last.after[1].is_none() {
                    last.after[1] = Some(context);
                } else {
                    let res = RgResult {
                        before: [Some(context), None],
                        ..Default::default()
                    };

                    self.push(res);
                }
            } else {
                last.before[1] = Some(context);
            }
        } else {
            let res = RgResult {
                before: [Some(context), None],
                ..Default::default()
            };

            self.push(res);
        }

        Ok(true)
    }
}

pub fn search_dir(
    dir: &Path,
    pattern: &str,
) -> Option<impl Iterator<Item = Result<(RgResults, Option<RgErr>), RgErr>>> {
    struct RgIter<W> {
        matcher: RegexMatcher,
        searcher: Searcher,
        walker: W,
    }

    impl<W> Iterator for RgIter<W>
    where
        W: Iterator<Item = Result<ignore::DirEntry, ignore::Error>>,
    {
        type Item = Result<(RgResults, Option<RgErr>), RgErr>;

        fn next(&mut self) -> Option<Self::Item> {
            let file = self.walker.next()?;

            let res = match file {
                Ok(file) => {
                    let mut printer = RgResults::from_path(file.path());
                    if let Err(e) =
                        self.searcher
                            .search_path(&self.matcher, file.path(), &mut printer)
                    {
                        Ok((printer, Some(RgErr::from(e))))
                    } else {
                        Ok((printer, None))
                    }
                }
                Err(e) => Err(RgErr::from(e)),
            };

            Some(res)
        }
    }

    let matcher = build_matcher(pattern).ok()?;
    let searcher = build_searcher();
    let walker = build_walker(dir);

    Some(RgIter {
        matcher,
        searcher,
        walker,
    })
}
