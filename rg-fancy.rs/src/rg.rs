use grep::regex::{self, RegexMatcher};
use grep::searcher::{Searcher, Sink, SinkContext, SinkMatch};

use std::path::Path;

fn build_walker<'a>(
    path: &Path,
    glob: impl Iterator<Item = &'a str>,
) -> impl Iterator<Item = Result<ignore::DirEntry, ignore::Error>> {
    use ignore::WalkBuilder;

    let mut builder = WalkBuilder::new(path);

    builder
        .follow_links(true)
        .max_filesize(Some(1_000_000_000))
        .threads(1)
        .hidden(false);
    let mut overrides = ignore::overrides::OverrideBuilder::new(path);
    overrides.add("!**/.git").ok();
    for glob in glob {
        overrides.add(glob).ok();
    }
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

fn build_searcher<const CONTEXT_LENGTH: usize>() -> Searcher {
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

//
// line_idx - 3: before[2]
// line_idx - 2: before[1]
// line_idx - 1: before[0]
// line_idx    : matched[0]
// line_idx + 1: after[0]
// line_idx + 2: after[1]
// line_idx + 3: after[2]
//
#[derive(Debug)]
pub struct RgResult<const CONTEXT_LENGTH: usize> {
    pub line_idx: Option<u64>,
    pub before: [Option<String>; CONTEXT_LENGTH],
    pub after: [Option<String>; CONTEXT_LENGTH],
    pub matched: Option<Vec<String>>,
}

impl<const CONTEXT_LENGTH: usize> Default for RgResult<CONTEXT_LENGTH> {
    fn default() -> Self {
        Self {
            line_idx: None,
            before: [const { None }; CONTEXT_LENGTH],
            after: [const { None }; CONTEXT_LENGTH],
            matched: None,
        }
    }
}

pub struct RgErr {
    pub msg: String,
}

impl RgErr {
    fn from(e: impl std::error::Error) -> Self {
        Self { msg: e.to_string() }
    }
}

impl<const CONTEXT_LENGTH: usize> RgResult<CONTEXT_LENGTH> {
    fn update_matched(&mut self, src: &SinkMatch<'_>) {
        self.line_idx = src.line_number();

        let lines = src
            .lines()
            .map(|line| String::from_utf8_lossy(line.trim_ascii_end()).into_owned())
            .collect();
        self.matched = Some(lines);
    }

    // ctxlen - this_none_end = this_none_end
    fn copy_before_from_prev(&mut self, prev: &Self) {
        // self.before
        // [ None, ..., None, Some 1, ..., Some K ]
        // 0..this_none_end: None
        // this_none_end..CONTEXT_LENGTH: Some
        let this_none_end = self.before_none_end();
        if this_none_end == 0 {
            return;
        }
        let this_none_range = 0..this_none_end;

        // prev.after
        // [ Some 1', ..., Some K', None, ..., None ]
        // 0..that_none_start: Some
        // that_none_start..CONTEXT_LENGTH: None
        let that_none_start = prev.after_none_start();
        let that_some_range = 0..that_none_start;

        if this_none_range.end <= that_some_range.end {
            // self.before
            // [ Some 1, ..., Some K, Some K', ..., Some * ]
            for i in 0..this_none_end {
                self.before[i] = prev.after[that_none_start - i - 1].clone();
            }
            self.before.rotate_left(this_none_end);
            return;
        }

        // self.before
        // [ Some K', ..., Some 1', None, ..., None, Some 1, ..., Some K ]
        // 0..that_none_start: Some
        // that_none_start..this_none_end: None
        // this_none_end..CONTEXT_LENGTH: Some
        for i in that_some_range {
            self.before[that_none_start - i - 1] = prev.after[i].clone();
        }

        let rest = this_none_end - that_none_start;
        let prev_match = prev.matched.as_ref().map(|matched| {
            let len = matched.len();
            if rest <= len {
                &matched[(len - rest)..len]
            } else {
                &matched[..]
            }
        });
        if let Some(prev_match) = prev_match {
            for (i, matched) in prev_match.iter().enumerate() {
                self.before[that_none_start + i] = Some(matched.clone());
            }
            if prev_match.len() < rest {
                let start = that_none_start + prev_match.len();
                let end = this_none_end;
                self.before[start..end].clone_from_slice(&prev.before[0..(end - start)]);
            }
        } else {
            let start = that_none_start;
            let end = this_none_end;
            self.before[start..end].clone_from_slice(&prev.before[0..(end - start)]);
        }
        self.before.rotate_left(this_none_end);
    }

    // self.before
    // [ None, ..., None, Some 1, ..., Some K ]
    // 0..none_end: None
    // none_end..CONTEXT_LENGTH: Some
    fn before_none_end(&self) -> usize {
        CONTEXT_LENGTH
            - self
                .before
                .iter()
                .rev()
                .enumerate()
                .find_map(|(i, item)| if item.is_some() { None } else { Some(i) })
                .unwrap_or(CONTEXT_LENGTH)
    }

    // self.after
    // [ Some 1, ..., Some K, None, ..., None ]
    // 0..none_start: Some
    // none_start..CONTEXT_LENGTH: None
    fn after_none_start(&self) -> usize {
        self.after
            .iter()
            .enumerate()
            .find_map(|(i, item)| if item.is_some() { None } else { Some(i) })
            .unwrap_or(CONTEXT_LENGTH)
    }

    fn append_to_before(&mut self, context: String) {
        let idx = self.before_none_end();
        if idx == 0 {
            self.before[CONTEXT_LENGTH - 1] = Some(context);
            self.before.rotate_right(1);
        } else {
            self.before[idx - 1] = Some(context);
        }
    }

    fn append_to_after(&mut self, context: String) -> Result<(), ()> {
        let idx = self.after_none_start();
        if idx == CONTEXT_LENGTH {
            Err(())
        } else {
            self.after[idx] = Some(context);
            Ok(())
        }
    }

    fn align_before(&mut self) {
        let idx = self.before_none_end();
        self.before.rotate_left(idx);
    }

    fn is_matched(&self) -> bool {
        self.matched.is_some()
    }

    fn context(ctx: &SinkContext<'_>) -> String {
        String::from_utf8_lossy(ctx.bytes().trim_ascii_end()).into_owned()
    }
}

#[derive(Debug)]
pub struct RgResults<const CONTEXT_LENGTH: usize> {
    inner: Vec<RgResult<CONTEXT_LENGTH>>,
    path: String,
}

struct LastResults<'a, const CONTEXT_LENGTH: usize> {
    last: Option<&'a mut RgResult<CONTEXT_LENGTH>>,
    second_last: Option<&'a mut RgResult<CONTEXT_LENGTH>>,
}

impl<const CONTEXT_LENGTH: usize> RgResults<CONTEXT_LENGTH> {
    fn from_path(path: &Path) -> Self {
        Self {
            inner: Default::default(),
            path: path_to_string(path),
        }
    }

    fn last_two_mut(&mut self) -> LastResults<'_, CONTEXT_LENGTH> {
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

    fn split_last_mut(
        &mut self,
    ) -> (
        Option<&mut RgResult<CONTEXT_LENGTH>>,
        &mut [RgResult<CONTEXT_LENGTH>],
    ) {
        if let Some((last, rest)) = self.inner.split_last_mut() {
            (Some(last), rest)
        } else {
            (None, Default::default())
        }
    }

    fn update_after(target: &mut [RgResult<CONTEXT_LENGTH>], src: &[String]) {
        for res in target.iter_mut().rev() {
            let idx = res.after_none_start();
            if idx == CONTEXT_LENGTH {
                return;
            }

            let clone_from_src = |after: &mut [Option<String>], src: &[String]| {
                for i in 0..after.len() {
                    after[i] = Some(src[i].clone());
                }
            };

            if idx + src.len() <= CONTEXT_LENGTH {
                clone_from_src(&mut res.after[idx..(idx + src.len())], src);
            } else {
                clone_from_src(&mut res.after[idx..], src);
            }
        }
    }

    fn push(&mut self, item: RgResult<CONTEXT_LENGTH>) {
        self.inner.push(item);
    }

    pub fn into_raw(self) -> (String, Vec<RgResult<CONTEXT_LENGTH>>) {
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
impl<const CONTEXT_LENGTH: usize> Sink for RgResults<CONTEXT_LENGTH> {
    type Error = std::io::Error;

    fn matched(&mut self, _searcher: &Searcher, mat: &SinkMatch<'_>) -> Result<bool, Self::Error> {
        let last_two = self.last_two_mut();

        if let Some(last) = last_two.last {
            if last.is_matched() {
                let mut res = RgResult::default();
                res.copy_before_from_prev(last);
                res.update_matched(mat);

                self.push(res);

                if let (Some(last), rest) = self.split_last_mut() {
                    Self::update_after(
                        rest,
                        last.matched.as_ref().map(AsRef::as_ref).unwrap_or_default(),
                    );
                }
            } else if let Some(second_last) = last_two.second_last {
                last.copy_before_from_prev(second_last);
                last.update_matched(mat);
            } else {
                last.align_before();
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
        let context = RgResult::<CONTEXT_LENGTH>::context(context);

        let last_two = self.last_two_mut();

        if let Some(last) = last_two.last {
            if last.is_matched() {
                if last.append_to_after(context.clone()).is_err() {
                    let mut res = RgResult::default();
                    res.before[CONTEXT_LENGTH - 1] = Some(context);

                    self.push(res);
                } else {
                    let (_, rest) = self.split_last_mut();
                    Self::update_after(rest, &[context]);
                }
            } else {
                last.append_to_before(context);
            }
        } else {
            let mut res = RgResult::default();
            res.before[CONTEXT_LENGTH - 1] = Some(context);

            self.push(res);
        }

        Ok(true)
    }
}

pub fn search_dir<'a, const CONTEXT_LENGTH: usize>(
    dir: &Path,
    pattern: &str,
    glob: impl Iterator<Item = &'a str>,
) -> Option<impl Iterator<Item = Result<(RgResults<CONTEXT_LENGTH>, Option<RgErr>), RgErr>>> {
    struct RgIter<W, const CONTEXT_LENGTH: usize> {
        matcher: RegexMatcher,
        searcher: Searcher,
        walker: W,
    }

    impl<W, const CONTEXT_LENGTH: usize> Iterator for RgIter<W, CONTEXT_LENGTH>
    where
        W: Iterator<Item = Result<ignore::DirEntry, ignore::Error>>,
    {
        type Item = Result<(RgResults<CONTEXT_LENGTH>, Option<RgErr>), RgErr>;

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
    let searcher = build_searcher::<CONTEXT_LENGTH>();
    let walker = build_walker(dir, glob);

    Some(RgIter {
        matcher,
        searcher,
        walker,
    })
}
