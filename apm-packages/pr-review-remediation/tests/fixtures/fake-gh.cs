#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Text.Json;

var scenario = Environment.GetEnvironmentVariable("FAKE_GH_SCENARIO") ?? "ready";
var statePath = Environment.GetEnvironmentVariable("FAKE_GH_STATE")
    ?? throw new InvalidOperationException("FAKE_GH_STATE is required.");

if (scenario == "gh-failure")
{
    Console.Error.WriteLine("simulated GitHub CLI failure");
    return 7;
}

if (args.Length >= 2 && args[0] == "pr" && args[1] == "view")
{
    if (scenario == "bad-json")
    {
        Console.WriteLine("{not-json");
        return 0;
    }

    var call = IncrementState(statePath);
    if (scenario == "prr-002")
    {
        var replayPullRequest = new
        {
            number = 123,
            title = "Goal Context review fixture",
            state = "OPEN",
            author = new { login = "fixture-user" },
            body = "Synthetic PRR-002 input.",
            url = "https://github.com/fixture/goal-context-review/pull/123",
            baseRefName = "main",
            baseRefOid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            headRefName = "feature",
            headRefOid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            isDraft = false,
            mergeable = "MERGEABLE",
            reviewDecision = "REVIEW_REQUIRED",
            statusCheckRollup = new object[]
            {
                new { id = 9001, name = "fixture-contract", status = "COMPLETED", conclusion = "SUCCESS" }
            },
            files = new object[]
            {
                new { path = "docs/handoff.md", additions = 1, deletions = 1 }
            }
        };
        Console.WriteLine(JsonSerializer.Serialize(replayPullRequest));
        return 0;
    }
    var headOid = scenario is "head-change" or "patch-head-change" && call >= 2 ? "head-002" : "head-001";
    var pullRequest = new
    {
        number = 123,
        title = "Fixture PR",
        state = "OPEN",
        author = new { login = "fixture-user" },
        body = "Fixture PR body",
        url = "https://github.com/example/repo/pull/123",
        baseRefName = "main",
        baseRefOid = "base-001",
        headRefName = "feature/review-fixture",
        headRefOid = headOid,
        isDraft = scenario == "draft",
        mergeable = "MERGEABLE",
        reviewDecision = "REVIEW_REQUIRED",
        statusCheckRollup = new object[]
        {
            new { name = "build", status = "COMPLETED", conclusion = "SUCCESS" },
            new { name = "tests", status = "COMPLETED", conclusion = "FAILURE" },
            new { name = "lint", status = "IN_PROGRESS", conclusion = "" }
        },
        files = new object[]
        {
            new { path = "src/Fixture.cs", additions = 3, deletions = 1 }
        }
    };
    Console.WriteLine(JsonSerializer.Serialize(pullRequest));
    return 0;
}

if (args.Length >= 2 && args[0] == "pr" && args[1] == "diff")
{
    if (scenario == "prr-002")
    {
        Console.WriteLine("diff --git a/docs/handoff.md b/docs/handoff.md");
        Console.WriteLine("index 1111111..2222222 100644");
        Console.WriteLine("--- a/docs/handoff.md");
        Console.WriteLine("+++ b/docs/handoff.md");
        Console.WriteLine("@@ -1 +1 @@");
        Console.WriteLine("-Phase 1 stops. Start Adaptive Implementation in a separate parent turn and retain the direct PR URL.");
        Console.WriteLine("+Continue with the remediation plan and retain the direct PR URL.");
        return 0;
    }

    Console.WriteLine("diff --git a/src/Fixture.cs b/src/Fixture.cs");
    Console.WriteLine("--- a/src/Fixture.cs");
    Console.WriteLine("+++ b/src/Fixture.cs");
    Console.WriteLine("@@ -1 +1 @@");
    Console.WriteLine("-return false;");
    Console.WriteLine("+return true;");
    return 0;
}

if (args.Length >= 2 && args[0] == "api")
{
    var endpoint = args[1];
    var call = ReadState(statePath);
    if (scenario == "prr-002")
    {
        if (endpoint.EndsWith("/reviews", StringComparison.Ordinal))
        {
            Console.WriteLine(Paginate(new object[]
            {
                new
                {
                    id = 700,
                    user = new { login = "copilot-pull-request-reviewer[bot]" },
                    body = "Copilot generated 1 comment",
                    state = "COMMENTED",
                    submitted_at = "2026-07-25T00:00:00Z",
                    commit_id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                }
            }));
            return 0;
        }

        if (endpoint.EndsWith("/issues/123/comments", StringComparison.Ordinal))
        {
            Console.WriteLine(Paginate(new object[]
            {
                new { id = 2700, user = new { login = "maintainer" }, body = "Keep Phase 1 read-only." }
            }));
            return 0;
        }

        if (endpoint.EndsWith("/pulls/123/comments", StringComparison.Ordinal))
        {
            Console.WriteLine(Paginate(new object[]
            {
                new
                {
                    id = 1700,
                    pull_request_review_id = 700,
                    commit_id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    original_commit_id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    user = new { login = "copilot-pull-request-reviewer[bot]" },
                    path = "docs/handoff.md",
                    line = 1,
                    body = "Preserve the direct PR URL."
                }
            }));
            return 0;
        }
    }

    if (endpoint.EndsWith("/reviews", StringComparison.Ordinal))
    {
        Console.WriteLine(Paginate(BuildReviews(scenario, call)));
        return 0;
    }

    if (endpoint.EndsWith("/issues/123/comments", StringComparison.Ordinal))
    {
        var comments = new object[]
        {
            new { id = 501, user = new { login = "maintainer" }, body = "Please preserve the public contract." }
        };
        Console.WriteLine(Paginate(comments));
        return 0;
    }

    if (endpoint.EndsWith("/pulls/123/comments", StringComparison.Ordinal))
    {
        Console.WriteLine(Paginate(BuildInlineComments(scenario, call)));
        return 0;
    }
}

Console.Error.WriteLine("unexpected fake gh invocation: " + string.Join(' ', args));
return 2;

static object[] BuildReviews(string scenario, int call)
{
    if (scenario is "timeout" or "head-change" or "inline-only"
        || (scenario == "inline-then-review" && call < 2))
    {
        return Array.Empty<object>();
    }

    var currentBody = scenario is "delayed" or "inline-then-review"
        ? "Copilot generated 2 comments"
        : "Copilot generated 1 comment";
    var current = new
    {
        id = 100,
        user = new { login = "copilot-pull-request-reviewer[bot]" },
        body = currentBody,
        state = "COMMENTED",
        submitted_at = "2026-07-25T00:00:00Z",
        commit_id = "head-001"
    };

    if (scenario == "lookalike-login")
    {
        return new object[]
        {
            new
            {
                id = 200,
                user = new { login = "my-copilot-helper[bot]" },
                body = "Lookalike generated 1 comment",
                state = "COMMENTED",
                submitted_at = "2026-07-26T00:00:00Z",
                commit_id = "head-001"
            },
            current
        };
    }

    if (scenario != "old-head")
    {
        return new object[] { current };
    }

    return new object[]
    {
        new
        {
            id = 90,
            user = new { login = "copilot-pull-request-reviewer[bot]" },
            body = "Copilot generated 3 comments",
            state = "COMMENTED",
            submitted_at = "2026-07-26T00:00:00Z",
            commit_id = "old-head"
        },
        current
    };
}

static object[] BuildInlineComments(string scenario, int call)
{
    if (scenario == "timeout" || scenario == "head-change")
    {
        return Array.Empty<object>();
    }

    var current = new List<object>
    {
        new
        {
            id = 1001,
            pull_request_review_id = 100,
            commit_id = "head-001",
            original_commit_id = "head-001",
            user = new { login = "copilot-pull-request-reviewer[bot]" },
            path = "src/Fixture.cs",
            line = 1,
            body = "Current-head finding"
        }
    };

    if ((scenario is "delayed" or "inline-then-review") && call >= 2)
    {
        current.Add(new
        {
            id = 1002,
            pull_request_review_id = 100,
            commit_id = "head-001",
            original_commit_id = "head-001",
            user = new { login = "copilot-pull-request-reviewer[bot]" },
            path = "tests/FixtureTests.cs",
            line = 10,
            body = "Delayed inline finding"
        });
    }

    if (scenario == "lookalike-login")
    {
        current.Add(new
        {
            id = 2001,
            pull_request_review_id = 200,
            commit_id = "head-001",
            original_commit_id = "head-001",
            user = new { login = "my-copilot-helper[bot]" },
            path = "src/Lookalike.cs",
            line = 1,
            body = "Lookalike finding"
        });
    }

    if (scenario == "old-head")
    {
        current.Add(new
        {
            id = 901,
            pull_request_review_id = 90,
            commit_id = "old-head",
            original_commit_id = "old-head",
            user = new { login = "copilot-pull-request-reviewer[bot]" },
            path = "src/Old.cs",
            line = 1,
            body = "Old-head finding"
        });
    }

    return current.ToArray();
}

static string Paginate(object[] items)
{
    var firstPage = items.Take(Math.Min(1, items.Length)).ToArray();
    var secondPage = items.Skip(firstPage.Length).ToArray();
    return JsonSerializer.Serialize(new object[] { firstPage, secondPage });
}

static int ReadState(string path)
{
    return File.Exists(path) && int.TryParse(File.ReadAllText(path), out var value) ? value : 0;
}

static int IncrementState(string path)
{
    var value = ReadState(path) + 1;
    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
    File.WriteAllText(path, value.ToString());
    return value;
}
