# focc.nvim

Local FastOlympicCoding-compatible test manager for Neovim 0.11+.
The plugin uses native Lua configuration. It never reads Sublime user settings.

## Start

Open a C++, Python, or Java source file. Run `:Focc run_all`.
The LazyVim specification is `~/.config/nvim/lua/plugins/focc.lua`.
It sets `.focc`, `:tests`, and `clang++ -std=c++26` for your workflow.
No global keymaps change. Use command completion after `:Focc `.

## Commands

| Command | Action |
| --- | --- |
| `:Focc run_all` | Compile and run all stored inputs. |
| `:Focc run 1` | Compile and run one test. Test numbers start at 1. |
| `:Focc show` | Show the existing results without rerunning. |
| `:Focc reload` | Reload tests after another editor changes them. |
| `:Focc add` / `edit 1` | Edit a test in a multiline form. Ctrl-S or `:FoccSave` saves. |
| `:Focc delete 1` / `clear` | Delete one test or clear all tests with confirmation. |
| `:Focc accept 1` / `reject 1` | Remember the last observed output. |
| `:Focc move_up 2` / `move_down 1` | Change test order. |
| `:Focc stop` | Cancel the active compiler or program. |
| `:Focc interactive` | Compile and start a program with live stdin. |
| `:Focc send` / `eof` | Send a line or close stdin. |
| `:Focc save_interactive` | Save captured input as a new unjudged test. |
| `:Focc stress` / `stop_stress` | Run or stop generator/reference/candidate tests. |
| `:Focc lint` | Request configured C++ diagnostics. |
| `:Focc snippets` | Insert a `.cpp` file from `algorithms_base`. |
| `:Focc debug 1` | Debug a C++ test through your configured nvim-dap adapter. |
| `:Focc debug_input_file` | Debug using `input.txt` beside the source. |
| `:Focc debug_no_input` | Debug with terminal stdin rather than a prepared file. |
| `:Focc receive [directory]` | Receive tests for the current source, or create problem files under a directory. |
| `:Focc stop_receive` | Stop the local receiver. |

The results panel has buffer-local keys. `r` runs one test. `R` runs all tests.
Single-test runs replace only that test's result and preserve other unchanged
tests' verdicts, output, and timing. Running all tests clears the previous results.
`a` adds, `e` edits, `d` deletes, `y` accepts, and `n` rejects output.
`J` and `K` move a test. Tab folds a test. `x` stops. `q` hides the panel.
`I` starts interactive input. `s` sends a line. `E` sends EOF. `S` saves captured input.

The panel shows a verdict summary and compact, colored status badges. Expanded tests
show Input, Expected (including alternatives), and Actual output. Empty stderr is
hidden. `]t` / `[t` jump to the next/previous test; `]f` / `[f` jump to failures
(wrong answers, runtime errors, timeouts, or output limits), without wrapping.
Selection and viewport stay anchored to the current test as earlier results grow.
`P` toggles automatic folding of accepted tests; Tab overrides folding for an
individual test. `v` toggles recorded rejected answers, hidden by default.
`D` debugs the selected test. `?` toggles the full shortcut help below the compact
footer. Failed tests remain expanded unless you explicitly fold them.
Normal crash results also show the termination signal, for example
`[RUNTIME ERROR] SIGSEGV`. Timeout/cancellation labels retain priority. `D` starts
a new debug execution of the selected test, not an inspection of the original run.

### Test editor

Add/edit opens one multiline form in the same bottom split as the previous JSON
editor. Enter or paste literal text below Input, Correct answer, and Incorrect
answer headings. Press Enter for a newline; no JSON escaping is needed. Input
preserves whitespace and trailing newlines exactly. New or edited answers trim
only surrounding whitespace, matching the existing output comparison. Unchanged
answer strings and unknown JSON fields remain intact.

`Ctrl-S` (normal or insert mode) and `:FoccSave` save and close the form. `:q!`
cancels without saving. In normal mode, Tab / Shift-Tab move between fields;
insert-mode Tab still inserts a tab. Leave headings unchanged. Saving refuses
deleted or changed headings and external changes to the test file.

An empty optional answer field creates no answer. To add another alternative, use
`:FoccAnswerAdd correct` or `:FoccAnswerAdd incorrect`. The first invocation in an
empty optional field enables that field as an answer, including an explicitly
empty answer. Subsequent invocations add another field. Use `:FoccAnswerDelete`
to remove the selected answer, rather than clearing it to an empty string.
The UI calls rejected answers "Incorrect", but stores them in FOCC's original
`uncorrect_answers` array. The saved format remains `.focc/<filename>:tests` JSON.
Saves use readable, tab-indented JSON with objects and nonempty answer arrays
on separate lines. Existing files are reformatted only when saved; string values
still use JSON escapes for embedded newlines.

## File compatibility

For `task.cpp`, tests live at `<source directory>/<tests_relative_dir>/task.cpp<tests_file_suffix>`.
Test files contain a JSON array with `test`, `correct_answers`, and `uncorrect_answers`.
The plugin preserves order and unknown fields. It refuses saves after an external change.
JSON formatting can change. The plugin never converts the file to another test format.
Only explicit edits write test files. Run commands do not change them.

Observed output has whitespace removed only at both ends for comparison.
Accepted answers take priority over rejected answers. If accepted answers exist,
output matching none of them is rejected. With no accepted answers, output remains
unknown unless it matches a recorded rejected answer. Judging never automatically
adds mismatches to `uncorrect_answers`; only an explicit reject/edit records them.
This differs from Sublime's unknown verdict for unrecognized output, but preserves
the shared test-file format.
Runtime errors and timeouts appear separately from answer status.
Neovim shows stderr separately. The original package merges stderr into stdout.

## Configuration

Use `opts` in the LazyVim specification, or call `require("focc").setup(opts)` in another configuration.
Each `run_settings` entry contains `name`, `extensions`, `compile_cmd`, `run_cmd`, and optional `lint_compile_cmd`.
Set `compile_cmd = false` for interpreted languages. Commands use argument arrays by default.
Command placeholders: `{file}` (full filename), `{source_file}` (absolute path),
`{source_file_dir}` (absolute directory), `{file_name}` (basename without extension), and `{args}`.
An array's `{args}` entry expands to `run_args`. It must be a separate argument.
Commands execute in the source directory. String commands require `allow_shell = true`.
Only use string commands from trusted configuration. Their quoting follows your template.

| Option | Default | Meaning |
| --- | --- | --- |
| `tests_relative_dir` | `""` | Directory relative to source. Your spec uses `.focc`. |
| `tests_file_suffix` | `":tests"` | Suffix appended to full filename. |
| `save_before_run` | `true` | Save a modified source before execution. |
| `allow_shell` | `false` | Permit trusted shell command strings. |
| `run_timeout_ms` | `5000` | Time limit for each regular or interactive process. |
| `compile_timeout_ms` | `30000` | Time limit for each compile. |
| `output_limit` | `1048576` | Maximum combined stdout/stderr bytes per process. |
| `run_args` | `{}` | Arguments inserted at `{args}`. No implicit `-debug`. |
| `panel_width` | `0.42` | Fraction of editor width for results. |
| `close_sidebar` | `false` | Close Neo-tree when opening results. |
| `lint_enabled` | `false` | Enable compiler diagnostics after edits. |
| `lint_delay_ms` | `700` | Delay after last edit. |
| `lint_error_region_scope` | `"DiagnosticError"` | Neovim highlight group for error spans. |
| `lint_warning_region_scope` | `"DiagnosticWarn"` | Neovim highlight group for warning spans. |
| `cpp_complete_enabled` | `true` | Supply shorthand completion with Ctrl-X Ctrl-U. |
| `cpp_complete_settings` | Original class definitions | Classes with `template_size`, optional `bind`, and `dont_expand`. |
| `algorithms_base` | `false` | Directory for `.cpp` snippets and optional `.cpp:properties`. |
| `numeric_highlights` | `false` | Mark digit groups using installed Tree-sitter captures. |
| `stress_time_limit_seconds` | `2` | Limit for each generator or solution process. |
| `stress_iterations` | `0` | Maximum iterations. Zero runs until stopped or failed. |
| `debug` | See below | Debug adapter, build, executable, and stdin settings. |
| `companion` | See below | Competitive Companion port, source language, template, and request limit. |

`run_settings` replaces the language list. Nested options otherwise merge with defaults.
The default language commands use g++ GNU C++17, Python, and Java.
Your LazyVim spec replaces these with your compiler choices.

For example, `vi` expands to `vector<int>` and `vpii` expands to `vector<pii>`.
Use Ctrl-X Ctrl-U to request shorthand completion. The LazyVim spec also adds a C++ Blink provider.
Other Blink providers remain available. No completion keymaps change.
Live lint uses a temporary copy, not the package's shared `amin.cpp` file.
Use `-fsyntax-only` in lint commands to prevent an unintended executable.

## Stress tests

Create `<name>__Good` and `<name>__Generator` beside the candidate source.
Their extensions can differ. Each must match a configured language.
The generator receives a decimal seed on stdin. The solutions receive generator stdout.
Stress output comparison trims both ends. A difference, crash, or timeout stops the run.
The failure input and seed appear in a separate buffer. They are not automatically saved.

## Current limits

This is the initial build, not full parity with Sublime FastOlympicCoding.
Codeforces submission is not implemented. Competitive Companion imports samples,
not hidden tests or full problem statements.
The plugin does not accept or store credentials.

## Competitive Companion downloads

Install the Competitive Companion browser extension and add `12345` to its custom
ports. Restart Neovim after installing this plugin update, then run:

```vim
:Focc receive ~/Projects/Protocol99/CP
```

Open a Codeforces problem or a contest's problem-list page and click the extension's
plus button. A contest sends one request per problem; notifications show batch progress.
The receiver continues listening until `:Focc stop_receive` or Neovim exit. It does
not start automatically, and a second Neovim cannot bind the same port concurrently.
With a directory argument, the receiver creates problem files under that directory.
Use `:Focc receive .` to select Neovim's current working directory explicitly.

Without a directory argument, the receiver imports samples for the currently open
named source file instead. For example, with `problem.cpp` open, `:Focc receive`
creates or appends to `.focc/problem.cpp:tests` beside that source. It does not
create a contest directory, rename/create/save the source, or overwrite existing
tests. A named source buffer can still be unsaved. Identical input/answer pairs
are not appended twice, and custom tests remain intact.

Each request uses the source buffer active when Neovim processes that request.
Switching buffers changes the destination for subsequent requests. A FOCC
results/editor buffer uses its associated source file. An unnamed or unsupported
active buffer rejects the import instead of reusing the previous source. Use an explicit
destination directory. Current-file mode rejects multi-problem batches to prevent
mixing a whole contest into one file; use an explicit directory for contest imports.
Stop the receiver before changing between current-buffer and explicit-directory modes.

With an explicit destination, contest 1234 problem A creates:

```text
<destination>/1234/A.cpp
<destination>/1234/.focc/A.cpp:tests
<destination>/1234/.focc/A.cpp:tests:problem.json
```

The destination is your chosen root; no judge-name directory is added for Codeforces,
AtCoder, or CodeChef. Choose separate roots for different judges if desired:

| Judge | Path relative to destination |
|---|---|
| Codeforces contest, problemset, or Gym | `<contest-id>/<problem-id>.cpp`, e.g. `1234/A.cpp` |
| AtCoder | `<contest-id>/<task-label>.cpp`, e.g. `abc400/A.cpp` |
| CodeChef contest | `<contest-code>/<problem-code>.cpp`, e.g. `START123D/PROBCODE.cpp` |
| CodeChef practice without a contest code | `Practice/<problem-code>.cpp` |

Single-problem and whole-contest downloads use the same mapping; batch arrival order
never determines filenames. AtCoder uses a single-letter task URL suffix, uppercased,
or the displayed task label for older/nonstandard URLs; if neither is available, it
keeps the full task slug. CodeChef uses problem codes rather than invented A/B letters.
For CodeChef practice URLs, an uppercase contest-code token in Companion's
`CodeChef - <code>` group is used when available; titles/syllabus names fall back to
`Practice`. A contest-scoped URL takes priority over the group. Problem, submit, and
legacy problems-old URLs are supported. If a practice payload has no contest code,
its original contest cannot be inferred and its path may differ from a contest import.

Other judges retain the sanitized group/problem-name fallback. Existing files from
the previous `Codeforces/<id>` layout are not moved; choose that existing `Codeforces`
directory as the destination to continue using them. Gym also uses `<id>` directly;
choose a separate Gym root if you want it separate from normal contests.

Source files default to empty `.cpp` files; existing solutions are never
overwritten. Samples are appended only when that input/expected-answer pair is new,
so reimporting preserves custom tests and does not duplicate unchanged samples.
Separate metadata records the problem URL and constraints and is created only if
absent. Importing does not compile or execute received content. Interactive problems
still require an interactor for actual interactive judging.

Configure `companion.port` (default `12345`), `extension` (default `"cpp"`, must
match a configured language), `template` (default `""`, literal source text for new
files), and `max_request_bytes` (default 2 MiB). The receiver uses Neovim's built-in
libuv: no Node, Python server, Mason package, or extra plugin is required.
It accepts bounded HTTP POSTs at `/` on `127.0.0.1` only, rejects generated symlink
paths, and times out incomplete requests. Use a destination without symlinked parents.
Debugging requires nvim-dap and an adapter that you install and configure separately.
File stdin uses codelldb-compatible `stdio`. Other adapters need additional integration.
Inspect variables and stack frames through nvim-dap commands.

## C++ debugging

Your LazyVim specification uses CodeLLDB and builds `<name>-debug` with
`clang++ -std=c++26 -g -O0`. Normal run executables are separate.
Enable `dap.core` in `:LazyExtras`, restart, and install `codelldb` with Mason.
The adapter must be registered in nvim-dap (DAP Core's Mason integration can do this).

`:Focc debug 1` extracts test 1's input from the shared JSON file into a temporary
stdin file. `:Focc debug` prompts for a stored test. Tests and expected answers are
not modified, and expected output is not automatically judged during debugging.
Temporary input is removed on process exit, session termination, or Neovim exit.
File-input launches also set LLDB's `target.input-path`, because console-mode
redirection on this machine needs it in addition to `stdio`.

`:Focc debug_input_file` reads `debug.input_file` (default `input.txt`), relative
to the source directory unless absolute. This existing file is never deleted.
`:Focc debug_no_input` requests an integrated terminal for manual input; it does
not provide an interactive judge or interactor.

Debug options: `adapter` (default empty), `compile_cmd` (default false),
`program` (default `"{source_file_dir}/{file_name}-debug"`), `input_file`
(default `"input.txt"`), and `stop_on_entry` (default true).
The compile command must produce the executable named by `program`.
All modes save the active source first when `save_before_run` is enabled.

Use LazyVim's `<leader>db` to toggle a breakpoint, `<leader>dc` to continue,
`<leader>di` to step into, `<leader>do` to step out, and `<leader>dO` to step over.
The DAP UI shows variables, watches, and stack frames. Stop on entry can be
disabled with `debug.stop_on_entry = false` without disabling breakpoints.
CodeLLDB's initial entry stop can be in the system loader rather than `main`.
Continue to your source breakpoint; missing loader source is not a build failure.

### Live crash inspection

When a debug execution stops on an exception (including SIGSEGV or SIGABRT), FOCC
opens nvim-dap-ui if installed and shows the stop description. Its REPL includes
the stop description and the nearest stack frame in the current source file.
FOCC selects that source frame when available; the full stack remains accessible,
including system-library frames. Without a source frame, nvim-dap retains the
adapter's selected frame. Missing debug information can limit variable inspection.

Select frames in the DAP UI Stacks pane to inspect their variables in Scopes.
LazyVim also provides `<leader>dj` / `<leader>dk` for frame selection and
`<leader>de` for expression evaluation. Use `<leader>dt` to terminate explicitly.
FOCC never automatically resumes or kills the process on a crash stop. It disables
nvim-dap's automatic continuation of additional stopped threads during this session
and restores the previous adapter default when the session closes. Temporary test
stdin stays available until process exit or debugger termination.

Normal test runs show runtime errors and signals but do not launch a debugger.
`D` or `:Focc debug N` repeats the test under CodeLLDB; the program must reproduce
the crash. No automatic repetition, confirmation prompt, or core-dump analysis is
implemented. Debugging and crash inspection do not modify shared test JSON.

Live fatal-signal checks: `nvim --headless -u NONE -l tests/crash.lua` from the
plugin directory. This test requires Mason CodeLLDB, nvim-dap, nvim-dap-ui, and
nvim-nio. It checks SIGSEGV/SIGABRT, opening the UI, source locations, variables,
frame selection, retained input, and cleanup after explicit termination.

An optional live CodeLLDB check is `nvim --headless -u NONE -l tests/debug.lua`
from this plugin directory. It requires the installed nvim-dap and Mason CodeLLDB.
Sublime pixel-level UI, multicursor input, and its OSX debugger are not reproduced.
Snippet property offsets use UTF-8 byte offsets. Original non-ASCII character offsets may differ.
Editing uses a JSON buffer rather than Sublime's input-only editor.
Input streams and stored tests are separate modes. Regular tests close stdin after sending input.
There is no automatic Tab abbreviation replacement in this build.

## Verification

Run `:checkhealth focc` for compiler and runtime checks.
From the plugin directory, run:

```sh
nvim --headless -u NONE -l tests/run.lua
```

Tests use temporary copies. They do not change your `CP/` files.
