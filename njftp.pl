#!perl
#
# njftp.pl ini_file_name
#	- multipurpose FTP script
#
# Written By:  Robert Eden, ADC Telecommunications, rmeden@yahoo.com 
#              Copyright 2001, ADC Telecommunications
#              No warrenty expressed or implied.
#              Script may be redistributed under the terms of Perl itself
#
# 01/04/00	reden	added EXECUTE command
# 02/04/00  	reden	fixed DIEing within EVAL from hitting __DIE__ signal.
#			redid return values from functions to work better with eval
# 06/07/01      reden   cleaned up a bit for distribution

use Net::FTP 2.33;
use Net::FTP::A;        # needed so compiler works
use Net::FTP::dataconn; # needed so compiler works
use Net::FTP::E;        # needed so compiler works
use Net::FTP::I;        # needed so compiler works
use Net::FTP::L;        # needed so compiler works

use Fcntl ':flock'; # import LOCK_* constants

select STDERR; $|=1;
select STDOUT; $|=1;


$CONFIG = shift;
unless ($CONFIG)
{
    print '
njftp   Version 1.0
*** Syntax: njftp config_file

(C) 2001 Robert Eden, ADC Telecommunications,  rmeden@yahoo.com
This script may be distributed under the same terms as Perl itself.
No warranty expressed or implied, etc.  Use at your own risk.

*************************************************************************
**** if you use this script, please drop me an email and say thanks! ****
****                        rmeden@yahoo.com                         ****
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

            SITE	site1	site1.com /usr/tmp user password
            SITE	site2   site2.com        . user password
            
            XMIT	BINARY UNSENT SENT \.cdr$ site1 myproxy
            XMIT	BINARY UNSENT SENT \.cdr$ site2
            
';
exit 99;
}


#
# define constants
#
$|=1;
%COMMAND=(     ENV  =>  \&set_env,
            LOGFILE  => \&set_logfile,
            FIREWALL => \&set_firewall,
            SITE     => \&set_site,
            XMIT     => \&process_xmit,
            GET      => \&process_get,
            GETD     => \&process_getd,
            UNZIPD   => \&process_unzipd,
	    EXECUTE  => \&process_execute,
	    WAITMIN  => \&process_waitmin,
	    DOEACHD  => \&process_doeachd,
            DOEACH   => \&process_doeach,
           );
           

$SIG{__WARN__} = sub {
                     print         localtime()." $_[0]";
                     print LOGFILE localtime()." $_[0]" if defined $LOGFILE;
                    };

$SIG{__DIE__} = sub {
                     print         "DIE! ".localtime()." $_[0]";
                     print LOGFILE "DIE! ".localtime()." $_[0]" if defined $LOGFILE;
		     exit 99;
                    };

#
# FIREWALL_TYPE=SBC     normal login to firewall, then to site
#
$FIREWALL_TYPE='SBC';

select STDERR; $|=1;
select STDOUT; $|=1;

#
# set date constants
#
	@date = localtime();
	$ENV{HHMM} = sprintf("%02d%02d",@date[2,1]);
	$ENV{HH}   = sprintf("%02d",$date[2]);
	$ENV{DD}   = sprintf("%02d",$date[3]);
	$ENV{MM}   = sprintf("%02d",$date[4]+1);
	$ENV{YY}   = substr($date[5]+1900,2,2);
	$ENV{YYYY} = $date[5]+1900;


#
# open INI file and process it (main loop)
#
warn "started CONFIG=$CONFIG ($$)\n";
open(INI,$CONFIG) or die "Can't open ini file $CONFIG";

while(<INI>)
{
    chomp;
    s/#.*//g;  # drop comments
    s/^\s+//;  # drop leading spaces
    s/\s+$//;  # drop trailing spaces
    ($cmd,@args)=split;
    $cmd=uc($cmd);
    next unless $cmd;
    unless (exists $COMMAND{$cmd})
    {
        warn "*WARNING* commmand $cmd not valid\n";
        next;
    }

    warn "calling $cmd(".join(",",@args).")\n" if $ENV{DEBUG};
    unless ( eval { 
                    local $SIG{__DIE__}=='';   # prevent die from exiting!
                    &{$COMMAND{$cmd}}(@args);
                  })
    {
	warn "*ERROR* $cmd(".join(",",@args).") returned $@\n";
	die "Exit on Error Requested\n" if $ENV{STOP_ERROR};
    }
} # INI file loop
close INI;
exit 0;

#
# set_env
#
sub set_env($$)
{
    $_ = $_[1];
    s!\$([A-Z]+)!$ENV{$1}!g;  #ENV substitution 
    $ENV{uc($_[0])}=$_;
    return 1;
}

#
# set_logfile
#
sub set_logfile($)
{
    $LOGFILE=$_[0];
    $LOGFILE =~ s!\$([A-Z]+)!$ENV{$1}!g;  #ENV substitution 
    if ($LOGFILE)
    {
        open(LOGFILE,">>$LOGFILE") or warn "Error opening logfile $LOGFILE\n";
        unless (flock(LOGFILE, &LOCK_EX + &LOCK_NB ))
        {
           close LOGFILE;
           $LOGFILE=undef;
           warn " **ERROR** Can't lock logfile $LOGFILE\n";
           exit 99;
        }
    }
    else
    {
        flock(LOGFILE,LOCK_UN+LOCK_NB);
        close LOGFILE;
    }
     return 1;
} #set_logfile

#
# set_firewall(name address user pass1 {pass2})
#
sub set_firewall($$$$;$)
{
    ($name,$add,$user,$pass1,$pass2)=@_;
    $name = uc($name);
    warn "firewall $name exists, overriding!\n" if exists $FIREWALL{$name};
    $FIREWALL{$name} = { ADDRESS => $add,
                         USER    => $user,
                         PASS1   => $pass1,
                         PASS2   => $pass2,
                       };
     return 1;
} # set_firewall

#
# set_site(name address dir user pass1 {pass2})
#
sub set_site($$$$$;$)
{
    ($name,$add,$dir,$user,$pass1,$pass2)=@_;
    $name = uc($name);
    $dir  = undef if $dir eq '.';
    
    warn "site $name exists, overriding!\n" if exists $SITE{$name};
    $SITE{$name} = {     ADDRESS => $add,
                         DIR     => $dir,
                         USER    => $user,
                         PASS1   => $pass1,
                         PASS2   => $pass2,
                    };
     return 1;
} # set_site

sub check_mode
{
    $mode = uc($mode);

    if   ($mode eq 'ASCII')
    {
       $MODE=0;
    }
    elsif ($mode eq 'TEXT')
    {
       $MODE=0;
    }
    elsif ($mode eq 'BINARY')
    {
       $MODE=1;
    }
    else
    {
        die "Mode ($mode) not ASCII or BINARY\n";
    }
} # check_mode

sub check_local_dir
{
    $dir = shift;
    $dir =~ s!\$([A-Z]+)!$ENV{$1}!g;  #ENV substitution 

    die "$dir not a directory" unless ( -d $dir );
    return $dir;
} #check_local_dir

#
#  check site
#
sub check_site
{
    $site = uc ($site);
    die "site $site not predefined\n" unless exists $SITE{$site};
    $SITE = $SITE{$site};
}

#
#  check firewall
#
sub check_firewall
{
    $FW='';
    $firewall_type='DIRECT';
    if ( $firewall )
    {
        $firewall = uc ($firewall);
        die "firewall $firewall not predefined\n" unless exists $FIREWALL{$firewall};
        $FW = $FIREWALL{$firewall};
        $firewall_type=$FIREWALL_TYPE;
    }
    else
    {
        $FW = undef;
    }
} # check_firewall


#
# FTP login routine
#
sub ftp_login
{
    #
# non-firewall login
#
    if ( $firewall_type eq 'DIRECT' )
    {
        warn ("opening direct FTP session with $$SITE{ADDRESS}\n") if $ENV{DEBUG};
        $ftp = Net::FTP ->new( $$SITE{ADDRESS},
                                   Debug   => ($ENV{DEBUG} || 0),
                                   Timeout => 30,
                                );

        die "Error ($@) connecting to $$SITE{ADDRESS}\n" unless $ftp;

        warn "FTP Login:$$SITE{USER},$$SITE{PASS1}\n" if $ENV{DEBUG};

        $st=$ftp->login($$SITE{USER},$$SITE{PASS1});
        if ( $$SITE{PASS2} and !$st )
        {
            warn "Login failure, trying second account password\n";
            warn "FTP Login:$$SITE{USER},$$SITE{PASS2}\n" if $ENV{DEBUG};

            $st=$ftp->login($$SITE{USER},$$SITE{PASS2});
        }
        
        die "FTP login error ($@)\n" unless $st;
    } # direct login
 
#
# connect via SBC firewall
#
    elsif ($firewall_type eq 'SBC' )
    {
# connect to firewall
        warn ("opening FTP session with $$FW{ADDRESS}\n") if $ENV{DEBUG};
        $ftp = Net::FTP ->new( $$FW{ADDRESS},
                                  Debug   => ( 0 || $ENV{DEBUG} ),
                                  Timeout => 30,
                                );
        die "Error ($@) connecting to $$FW{ADDRESS}\n" unless $ftp;

	$st=1;
	if (defined $$FW{USER})
        {
            warn "FW Login:'$$FW{USER},$$FW{PASS1}\n'" if $ENV{DEBUG};
            $st=$ftp->login($$FW{USER},$$FW{PASS1});
        }
 
        if ( $$FW{PASS2} and !$st )
        {
            warn "Login failure, trying second firewall password\n";
            warn "FW2 Login:'$$FW{USER},$FW{PASS2}'" if $ENV{DEBUG};
            $st=$ftp->login($$FW{USER},$$FW{PASS2});
        }
        
        die "Firewall login error ($@)\n" unless $st;

# login to site
        warn "Site Login:'$$SITE{USER}\@$$SITE{ADDRESS},$$SITE{PASS1}'\n" if $ENV{DEBUG};
        $st=$ftp->login("$$SITE{USER}\@$$SITE{ADDRESS}",$$SITE{PASS1});

        if ( $$SITE{PASS2} and !$st )
        {
            warn "Login failure, trying second site password\n";
            warn "Site Login:'$$SITE{USER}\@$$SITE{ADDRESS},$$SITE{PASS2}'" if $ENV{DEBUG};
            $st=$ftp->login("$$SITE{USER}\@$$SITE{ADDRESS}",$$SITE{PASS2});
        }
        
        die "Site login error ($@)\n" unless $st;
    } # SBC style firewall login
    else
    {
        die "Unknown Firewall type $FW\n";
    }

#
# set mode
#
    $st = $ftp->binary     if $MODE;
    $st = $ftp->ascii  unless $MODE;
    die "Error ($@) setting mode\n" unless $st;

#
# setting remote directory
#
    if ( $$SITE{DIR} )
    {
        $st = $ftp->cwd($$SITE{DIR}) if $$SITE{DIR};
        die "Error ($@) setting remote directory to $$SITE{DIR}\n" unless $st;
    }

   return 1;
  
} # ftp_login

#
# XMIT mode unsent_dir sent_dir pattern site {firewall}
#
sub process_xmit($$$$$;$)
{
    $@='';
#
# check arguments
#
     $mode       = shift or die '      mode not defined';
     $unsent_dir = shift or die 'unsent_dir not defined';
     $sent_dir   = shift or die '  sent_dir not defined';
     $pattern    = shift or die'    pattern not defined';
     $site       = shift or die'       site not defined';
     $firewall   = shift;

    &check_mode;
    &check_site;
    &check_firewall;
    
    $unsent_dir = &check_local_dir($unsent_dir);
    $sent_dir   = &check_local_dir($sent_dir);


#
# look for files
#
     @files=();
     warn "Scanning $unsent_dir for $pattern\n" if $ENV{DEBUG};
     opendir(DIR,$unsent_dir) or die "Cannot open dir $unsent_dir";
         @files = grep( /$pattern/i, readdir(DIR) );
         closedir(DIR);

    if ($ENV{DEBUG})
    {
        $_ = $#files+1;
        warn "Found $_ files in $unsent_dir matching /$pattern/i\n";
    }
    return 1 if $#files == -1; # nothing to do if no files!
    
&ftp_login;

#
# send files
#
    foreach $file (@files)
    {
	 warn "File loop processing $file\n" if $ENV{DEBUG};
         $unsent_file="$unsent_dir/$file";
         $sent_file  ="$sent_dir/$file";
    
# Integrety check... if these fire, something really wierd broke
# play it safe... don't transmit again until figured out!
        die "$unsent_file missing!\n"  unless -e $unsent_file;
        die "$sent_file already exists!\n" if -e $sent_file;

# send the temp file
	warn "sending $unsent_file as $$.tmp\n";
        $st = $ftp->put("$unsent_file","$$.tmp");
        die "Error ($@) sending $unsent_file as $$.tmp\n" unless $st;

# transfered ok, rename it to proper name
        $st = $ftp->rename("$$.tmp",$file);
        die "Error ($@) renaming $$.file to $file\n" unless $st;

#       $st = $ftp->delete($file); # debug only

# move copy to sent dir
        $st = rename $unsent_file, $sent_file;
        warn "rename $unsent_file $sent_file returned $st\n" if $ENV{DEBUG};
        die "Error ($@) renaming local $unsent_file -> $sent_file\n" unless $st;

# integrety check... file should have moved
        die "$unsent_file still exists!\n" if     -e $unsent_file;
        die "$sent_file doesn't exists!\n" unless -e $sent_file;
    } # send loop

    $ftp->quit();
    return 1;
    
} # process_xmit


#
# get mode local_dir pattern site {firewall}
#
sub process_get($$$$$;$)
{
    $@='';
#
# check arguments
#
     $mode       = shift or die '      mode not defined';
     $local_dir  = shift or die ' local_dir not defined';
     $pattern    = shift or die'    pattern not defined';
     $site       = shift or die'       site not defined';
     $firewall   = shift;
     $ftp = $st = '';

    &check_mode;
    &check_site;
    &check_firewall;
    
    $local_dir = &check_local_dir($local_dir);

&ftp_login;

#
# get list of files
#
    @files = $ftp->ls();
    if ($ENV{DEBUG})
    {
        foreach (@files)
        {
            warn "Found file: $_\n";
        }
    }

    foreach (grep(/$pattern/i,@files))
    {
        warn "About to fetch $_\n";
        $st = $ftp->get($_,"$$.tmp");
        die "Error ($@) getting $_ as $$.tmp" unless $st;
        rename "$$.tmp","$local_dir/$_" or die "Error $? on rename!\n";
    }
    $ftp -> quit();

return 1;

} # process_get

sub process_getd($$$$$;$)
{
    $@='';
#
# check arguments
#
     $mode       = shift or die '      mode not defined';
     $local_dir  = shift or die ' local_dir not defined';
     $pattern    = shift or die'    pattern not defined';
     $site       = shift or die'       site not defined';
     $firewall   = shift;
     $ftp = $st = '';

    &check_mode;
    &check_site;
    &check_firewall;
    
    $local_dir = &check_local_dir($local_dir);

     &ftp_login;

#
# get list of files
#
    @files = $ftp->ls();
    if ($ENV{DEBUG})
    {
        foreach (@files)
        {
            warn "Found file: $_\n";
        }
    }

    foreach (grep(/$pattern/i,@files))
    {
        warn "About to fetch $_\n";
        $st = $ftp->get($_,"$$.tmp");
        die "Error ($@) getting $_ as $$.tmp" unless $st;
        rename "$$.tmp","$local_dir/$_" or die "Error $? on rename!\n";
        $st = $ftp->delete($_) or die "Error $st on delete\n";
    }

$ftp -> quit();
return 1;

} # process_getd

#
# unzip 
#
sub process_unzipd
{
    $@='';
#
# check arguments
#
     $local_dir  = shift or die ' local_dir not defined';
     $password   = shift;
     $ftp = $st = '';

    $local_dir = &check_local_dir($local_dir);

#
# get list of files
#
    chdir $local_dir;
    
    opendir(DIR,".") or die "can't open directory\n";
    @files = grep(/\.zip/i,readdir(DIR));
    closedir(DIR);
    
    if ($ENV{DEBUG})
    {
        foreach (@files)
        {
            warn "Found file: $_\n";
        }
    }

    foreach (@files)
    {
        warn "Unzipping $_\n";
        $PASS = "";
        $PASS = "-s$password" if $password;
        $UNZIP='pkunzip';
        $UNZIP=$ENV{UNZIP} if exists $ENV{UNZIP};
        $cmd="$UNZIP -o $PASS $_ >FTP.log";
        warn "about to execute $cmd\n" if $ENV{DEBUG};
        system("$cmd");
        if ($?)
        {
           $st = '';
           $st = 'BAD PASSWORD'   if $? == 2816;
           $st = 'FILE NOT FOUND' if $? == 2304;
           warn "$st($?) error on $cmd\n";
        }
        else
        {
           unlink $_ or die "Error deleting $_\n";
        }
    } # file loop

return 1;

} # process_unzipd


#
# execute 
#
sub process_execute
{

    $@='';
#
# get arguments
#
  $outfile    = shift;
  $cmd        = join(" ",@_);

# replace $ codes with ENVIORNMENT variables
  $outfile =~ s!\$([A-Z]+)!$ENV{$1}!g;
  $cmd     =~ s!\$([A-Z]+)!$ENV{$1}!g;

#
# execute program 
#
  warn "about to execute $cmd >>$outfile\n" if     $ENV{DEBUG};
  warn "about to execute $_[0]\n"           unless $ENV{DEBUG};

  system("$cmd >>$outfile");
  warn "exit status $? \n" if $ENV{DEBUG};

   die "Error $? on $cmd >$outfile\n" if $?;

   return 1;

} # process_execute

#
# waitmin - wait until a specific minute
#
sub process_waitmin
{

    $@='';
#
# get arguments
#
  $waitmin    = shift;

#
# calculate sleep time (@date set at the start of the program)
#
  $sleep      = ((60 + $waitmin - $date[1] ) % 60) * 60  - $date[0] + 5;
  $sleep      = 3600 - $date[0] + 5 if $sleep < 0; # special case for same minute start
  warn "sleeping for $sleep seconds (until $waitmin)\n";
  sleep $sleep;
#
# set date constants
#
	@date = localtime();
	$ENV{HHMM} = sprintf("%02d%02d",@date[2,1]);
	$ENV{HH}   = sprintf("%02d",$date[2]);
	$ENV{DD}   = sprintf("%02d",$date[3]);
	$ENV{MM}   = sprintf("%02d",$date[4]+1);
	$ENV{YY}   = substr($date[5]+1900,2,2);
	$ENV{YYYY} = $date[5]+1900;

   return 1;

} # process_waitmin

#
# doeachd
#
sub process_doeachd
{

    $@='';
#
# get arguments
#
     $local_dir  = shift or die ' local_dir not defined';
     $pattern    = shift or die'    pattern not defined';
     $Ooutfile    = shift;
     $Ocmd        = join(" ",@_);

     $local_dir = &check_local_dir($local_dir);

#
# look for files
#
     @files=();
     warn "Scanning $local_dir for $pattern\n" if $ENV{DEBUG};
     opendir(DIR,$local_dir) or die "Cannot open dir $local_dir";
         @files = grep( /$pattern/i, readdir(DIR) );
         closedir(DIR);

    foreach $FILE (@files)
    {
        warn "About to process $FILE\n";
        $ENV{FILE}=$FILE;

# replace $ codes with ENVIORNMENT variables

        $outfile = $Ooutfile;
        $outfile =~ s!\$([A-Z]+)!$ENV{$1}!g;
        $outfile =~ s!\${([A-Z]+)}!$ENV{$1}!g;

        $cmd     = $Ocmd;
        $cmd     =~ s!\$([A-Z]+)!$ENV{$1}!g;
        $cmd     =~ s!\${([A-Z]+)}!$ENV{$1}!g;

        
#
# execute program 
#
      warn "about to execute $cmd >>$outfile\n" if     $ENV{DEBUG};
      warn "about to execute $_[0]\n"           unless $ENV{DEBUG};

      system("$cmd >>$outfile");
      warn "exit status $? \n" if $ENV{DEBUG};

      die "Error $? on $cmd >>$outfile\n" if $?;
      unlink $FILE;
   } # file loop
   return 1;

} # process_doeachd

#
# doeach
#
sub process_doeach
{

    $@='';
#
# get arguments
#
     $local_dir  = shift or die ' local_dir not defined';
     $pattern    = shift or die'    pattern not defined';
     $Ooutfile    = shift;
     $Ocmd        = join(" ",@_);

     $local_dir = &check_local_dir($local_dir);

#
# look for files
#
     @files=();
     warn "Scanning $local_dir for $pattern\n" if $ENV{DEBUG};
     opendir(DIR,$local_dir) or die "Cannot open dir $local_dir";
         @files = grep( /$pattern/i, readdir(DIR) );
         closedir(DIR);

    foreach $FILE (@files)
    {
        warn "About to process $FILE\n";
        $ENV{FILE}=$FILE;

# replace $ codes with ENVIORNMENT variables

        $outfile = $Ooutfile;
        $outfile =~ s!\$([A-Z]+)!$ENV{$1}!g;
        $outfile =~ s!\${([A-Z]+)}!$ENV{$1}!g;

        $cmd     = $Ocmd;
        $cmd     =~ s!\$([A-Z]+)!$ENV{$1}!g;
        $cmd     =~ s!\${([A-Z]+)}!$ENV{$1}!g;

        
#
# execute program 
#
      warn "about to execute $cmd >>$outfile\n" if     $ENV{DEBUG};
      warn "about to execute $_[0]\n"           unless $ENV{DEBUG};

      system("$cmd >>$outfile");
      warn "exit status $? \n" if $ENV{DEBUG};

      die "Error $? on $cmd >>$outfile\n" if $?;
   } # file loop
   return 1;

} # process_doeach


