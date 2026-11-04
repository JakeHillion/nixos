require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

if environment :matches "imap.mailbox" "*" {
  set "mailbox" "${1}";
}

# Moving spam to the bin isn't a sign it was ham
if string "${mailbox}" "Trash" {
  stop;
}

pipe :copy "learn-ham";
