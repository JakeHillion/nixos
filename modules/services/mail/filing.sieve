require ["fileinto", "index"];

if header :is "X-Spam" "yes" {
  fileinto "Junk";
} elsif allof (header :index 1 :is "Delivered-To" "archives@jakehillion.me",
               address :is "Resent-From" "jakehillion@live.co.uk") {
  fileinto "Archived Accounts/jakehillion@live.co.uk";
} elsif allof (header :index 1 :is "Delivered-To" "archives@jakehillion.me",
               address :is "Resent-From" "jshillion@hotmail.co.uk") {
  fileinto "Archived Accounts/jshillion@hotmail.co.uk";
}
