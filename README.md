# backup
Perl script for backup server  

# Setup
Run backup.pl with cron at the desired frequency on the backup server  
The server needs to be able to ssh into each computer it should backup without a password, to do so  
On the server:  
`ssh-keygen -t rsa` (Leave passphrase blank)  
`ssh-copy-id -i ~/.ssh/id_rsa.pub user@computer` (Repeat for every computer to backup, user should have permission to access all the files to backup)  
Perl module IPC::System::Simple required
