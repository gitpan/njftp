njftp   Version 1.1
*** Syntax: njftp config_file

(C) 2001 Robert Eden, ADC Telecommunications,  rmeden@yahoo.com
This script may be distributed under the same terms as Perl itself.
No warranty expressed or implied, etc.  Use at your own risk.

*************************************************************************
**** if you use this script, please drop me an email and say thanks! ****
****                        reden@cpan.org                           ****
*************************************************************************

This programs allows you to FTP files as well as do other things.  It is "not just FTP!".
It was designed to run on a schedule at a client site, download a file, and delete it off the
server ( to tell me it got the file ).  It has since grown significantly from there.

INI Format notes:
	    everything to the right of a # is ignored
	    leading whitespace is ignored
	    blank lines are ignored
	    command is not case sensistive
	    parameters are case sensitive
	    parameters are whitespace separated, cannot contain whitespace or #.
	    string substition with environment variables is supported via "$"
            Enviornment variables "$MM,$DD,$YY,$HH,$HHMM" are defined automatically.

INI Commands
     LOGFILE    logfile
    	logfile location

     ENV 	name value
 	    set enviornment variable

     FIREWALL name address {user pass1 {pass2}}

     SITE name address directory user pass1 {pass2} 

     XMIT ASCII|BINARY unsent_dir sent_dir pattern site {firewall}
        sends files matching regular expression pattern in <unsent_dir>.
    	files are moved from <unsent_dir> to <sent_dir> after success

     get ASCII|BINARY local_dir pattern site {firewall}
        gets files matching regular expression pattern "pattern".
    	files are saved in local_dir after successfull transmission. 

     getd ASCII|BINARY local_dir pattern site {firewall}
        same as get, but deletes file from server
        
     unzip local_dir {password} (calls PKUNZIP to unpack file)

     execute output command {args}
         execute command, sending stdout to "output"

     waitmin  min
    	sleeps until the current minutes = min

     doeach localdir pattern stdout command {args}
        executes command with file matching pattern.
        command should include $FILE enviornment variable

     doeachd localdir pattern stdout command {args}
        same as doeach
        file deleted if successfull
   
 notes:
	Environment variable DEBUG adds debugging info
	Environment variable STOP_ERROR terminates program on command error.
	a write lock is required for log file. (prevents multiple executions)
	pass2 is tried if pass1 fails (to allow for scheduled password changes)
	pattern is a regular expression, *NOT* a glob
	if "unsent_dir" matches an enviornment variable, it is replaced
	if   "sent_dir" matches an enviornment variable, it is replaced
	records are processed *IN ORDER*.
	file and directories names can use forward or back slash (perl IO)
	files are transmitted as temporary files, renamed to correct file
	    on success.	

sample:
            ENV	debug 	   1
    	    ENV STOP_ERROR 0
            ENV	UNSENT	C:/temp/unsent
            ENV	SENT	c:\temp\sent

            FIREWALL myproxy server user pass

            SITE	site1	site1.com /usr/tmp user password
            SITE	site2   site2.com        . user password
            
            XMIT	BINARY UNSENT SENT \.cdr$ site1 myproxy
            XMIT	BINARY UNSENT SENT \.cdr$ site2
