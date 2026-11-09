require ["fileinto", "index"];

if header :is "X-Spam" "yes" {
  fileinto "Junk";
} elsif allof (header :index 1 :is "Delivered-To" "archives@jakehillion.me",
               address :is "Resent-From" "jakehillion@live.co.uk") {
  fileinto "Archived Accounts/jakehillion@live.co.uk";
} elsif allof (header :index 1 :is "Delivered-To" "archives@jakehillion.me",
               address :is "Resent-From" "jshillion@hotmail.co.uk") {
  fileinto "Archived Accounts/jshillion@hotmail.co.uk";
} elsif anyof (address :is ["To", "Cc"] ["linux-kernel-announce@vger.kernel.org",
                                         "linux-kernel@vger.kernel.org",
                                         "linux-bcachefs@vger.kernel.org",
                                         "netdev@vger.kernel.org",
                                         "sched-ext@lists.linux.dev",
                                         "std-proposals@lists.isocpp.org"],
               address :is "From" ["noreply@crates.io",
                                   "notifications@llvm.discoursemail.com",
                                   "std-proposals-request@lists.isocpp.org"],
               header :is "X-GitHub-Sender" ["chatgpt-codex-connector[bot]",
                                             "github-merge-queue[bot]"]) {
  fileinto "Dev Lists";
}
