#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Text.Json;

var scenario = Environment.GetEnvironmentVariable("FAKE_GH_SCENARIO") ?? "ready";
var statePath = Environment.GetEnvironmentVariable("FAKE_GH_STATE")
    ?? throw new InvalidOperationException("FAKE_GH_STATE is required.");
var sameParentHead = Environment.GetEnvironmentVariable("FAKE_GH_HEAD_OID")
    ?? "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

if (args.Length >= 2 && args[0] == "repo" && args[1] == "view" && scenario.StartsWith("same-parent", StringComparison.Ordinal))
{
    Console.WriteLine("{\"nameWithOwner\":\"fixture/goal-context-review\"}");
    return 0;
}

if (args.Length >= 2 && args[0] == "pr" && args[1] == "list" && scenario.StartsWith("same-parent", StringComparison.Ordinal))
{
    var isHeadQuery = args.Contains("--head", StringComparer.Ordinal);
    var first = new
    {
        number = 123,
        url = "https://github.com/fixture/goal-context-review/pull/123",
        state = "OPEN",
        isDraft = scenario == "same-parent-draft",
        baseRefOid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        headRefOid = sameParentHead
    };
    var second = new
    {
        number = 124,
        url = "https://github.com/fixture/goal-context-review/pull/124",
        state = "OPEN",
        isDraft = false,
        baseRefOid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        headRefOid = sameParentHead
    };
    object[] result = scenario switch
    {
        "same-parent-missing" => [],
        "same-parent-ambiguous" when isHeadQuery => [],
        "same-parent-ambiguous" => [first, second],
        "same-parent-branch-priority" when isHeadQuery => [second],
        "same-parent-branch-priority" => [first, second],
        _ => [first]
    };
    Console.WriteLine(JsonSerializer.Serialize(result));
    return 0;
}

if (args.Length >= 2 && args[0] == "pr" && args[1] == "edit" && scenario.StartsWith("same-parent", StringComparison.Ordinal))
{
    if (scenario == "same-parent-review-request-failure")
    {
        Console.Error.WriteLine("simulated Copilot review request failure");
        return 8;
    }
    File.WriteAllText(statePath + ".copilot-requested", string.Join(' ', args));
    return 0;
}

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
    if (scenario.StartsWith("same-parent", StringComparison.Ordinal))
    {
        var requestedNumber = args.Length > 2 && int.TryParse(args[2], out var parsedNumber) ? parsedNumber : 123;
        var sameParentPullRequest = new
        {
            number = requestedNumber,
            title = "Same-parent Goal Context review fixture",
            state = scenario == "same-parent-closed" ? "CLOSED" : "OPEN",
            author = new { login = "fixture-user" },
            body = "Synthetic same-parent input.",
            url = $"https://github.com/fixture/goal-context-review/pull/{requestedNumber}",
            baseRefName = "main",
            baseRefOid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            headRefName = "feature",
            headRefOid = sameParentHead,
            isDraft = scenario == "same-parent-draft",
            mergeable = "MERGEABLE",
            reviewDecision = "REVIEW_REQUIRED",
            statusCheckRollup = new object[] { new { id = 9001, name = "fixture-contract", status = "COMPLETED", conclusion = "SUCCESS" } },
            files = new object[] { new { path = "src/Fixture.cs", additions = 1, deletions = 1 } }
        };
        Console.WriteLine(JsonSerializer.Serialize(sameParentPullRequest));
        return 0;
    }
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
    if (scenario.StartsWith("same-parent", StringComparison.Ordinal))
    {
        Console.WriteLine("diff --git a/src/Fixture.cs b/src/Fixture.cs");
        Console.WriteLine("--- a/src/Fixture.cs");
        Console.WriteLine("+++ b/src/Fixture.cs");
        Console.WriteLine("@@ -1 +1 @@");
        Console.WriteLine("-return false;");
        Console.WriteLine("+return true;");
        return 0;
    }
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
    if (scenario.StartsWith("same-parent", StringComparison.Ordinal))
    {
        if (endpoint.EndsWith("/reviews", StringComparison.Ordinal))
        {
            Console.WriteLine(Paginate(new object[]
            {
                new { id = 700, user = new { login = "copilot-pull-request-reviewer[bot]" }, body = scenario == "same-parent-review-only" ? "No findings." : "Copilot generated 1 comment", state = "COMMENTED", submitted_at = "2026-07-25T00:00:00Z", commit_id = sameParentHead }
            }));
            return 0;
        }
        if (endpoint.Contains("/issues/", StringComparison.Ordinal) && endpoint.EndsWith("/comments", StringComparison.Ordinal))
        {
            Console.WriteLine(Paginate(Array.Empty<object>()));
            return 0;
        }
        if (endpoint.Contains("/pulls/", StringComparison.Ordinal) && endpoint.EndsWith("/comments", StringComparison.Ordinal))
        {
            Console.WriteLine(Paginate(scenario == "same-parent-review-only"
                ? Array.Empty<object>()
                : new object[]
                {
                    new { id = 1700, pull_request_review_id = 700, commit_id = sameParentHead, original_commit_id = sameParentHead, user = new { login = "copilot-pull-request-reviewer[bot]" }, path = "src/Fixture.cs", line = 1, body = "Preserve the Goal Context boundary." }
                }));
            return 0;
        }
    }
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

    var currentBody = scenario == "review-only"
        ? "No findings."
        : scenario is "delayed" or "inline-then-review"
            ? "Copilot generated 2 comments"
            : "Copilot generated 1 comment";
    object currentUser = scenario == "copilot-app-url"
        ? new { login = "renamed-reviewer[bot]", html_url = "https://github.com/apps/copilot-pull-request-reviewer" }
        : new { login = "copilot-pull-request-reviewer[bot]" };
    var current = new
    {
        id = 100,
        user = currentUser,
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
    if (scenario is "timeout" or "head-change" or "review-only")
    {
        return Array.Empty<object>();
    }

    object currentUser = scenario switch
    {
        "copilot-actor-alias" => new { login = "Copilot" },
        "copilot-app-url" => new { login = "renamed-reviewer[bot]", html_url = "https://github.com/apps/copilot-pull-request-reviewer" },
        _ => new { login = "copilot-pull-request-reviewer[bot]" }
    };
    var current = new List<object>
    {
        new
        {
            id = 1001,
            pull_request_review_id = 100,
            commit_id = "head-001",
            original_commit_id = "head-001",
            user = currentUser,
            path = "src/Fixture.cs",
            line = 1,
            body = "Current-head finding"
        }
    };

    if (scenario == "copilot-human-reply")
    {
        current.Add(new
        {
            id = 1003,
            pull_request_review_id = 100,
            in_reply_to_id = 1001,
            commit_id = "head-001",
            original_commit_id = "head-001",
            user = new { login = "maintainer" },
            path = "src/Fixture.cs",
            line = 1,
            body = "Human reply to the Copilot comment"
        });
    }

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
