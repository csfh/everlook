import unittest

import risky_uses as risky

DIFF = """diff --git a/Everlook_X/x.lua b/Everlook_X/x.lua
--- a/Everlook_X/x.lua
+++ b/Everlook_X/x.lua
@@ -1,2 +1,6 @@
+local ok = loadstring(text)
+-- a comment that mentions SendMail is not a use
+TakeInboxMoney(index)
+local plain = 1 + 2
+RepairAllItems(false)
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -1 +1,2 @@
+      - run: echo hi
diff --git a/gone.lua b/gone.lua
--- a/gone.lua
+++ /dev/null
@@ -1 +0,0 @@
-SendMail()
"""


class RiskyUsesTest(unittest.TestCase):
    def test_added_lines_are_listed_by_reason_and_comments_and_plain_lines_are_not(self):
        found = risky.scan(DIFF, "addon")
        reasons = [reason for reason, _ in found["Everlook_X/x.lua"]]
        self.assertEqual(reasons, ["runs text as code", "mail", "repair, selling, buying or deleting items"])

    def test_a_changed_workflow_is_listed_as_such(self):
        self.assertEqual(risky.scan(DIFF, "addon")[".github/workflows/ci.yml"][0][0], "a workflow or release script changed")

    def test_removed_lines_and_deleted_files_are_not_listed(self):
        self.assertNotIn("gone.lua", risky.scan(DIFF, "addon"))

    def test_a_changed_release_script_is_listed_by_its_path_from_the_repository_root(self):
        found = risky.scan("+++ b/addon/scripts/pack.sh\n+echo packed\n", "addon")
        self.assertEqual(found["addon/scripts/pack.sh"][0][0], "a workflow or release script changed")

    def test_a_clean_diff_says_so(self):
        self.assertIn("No added line", risky.render(risky.scan("+++ b/a.lua\n+local x = 1\n", "addon")))

    def test_the_summary_never_raises(self):
        self.assertIn("### `Everlook_X/x.lua`", risky.render(risky.scan(DIFF, "addon")))


if __name__ == "__main__":
    unittest.main()
