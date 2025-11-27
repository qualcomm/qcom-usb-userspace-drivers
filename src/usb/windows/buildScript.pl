require 5.0;

use FileHandle;
use vars qw(%opts);
use Cwd;
sub TRACE;
sub TimeLog;
sub Run;
sub ExitScript;
sub BuildVSProject;
sub updateVersions;
sub BuildQikInstaller;

use strict;
#use Win32::InstallShield;
use List::Util qw(first);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

#----------------------------------------------------------------------------
# Drivers to build 
#----------------------------------------------------------------------------
# Set $Rebuild to "Rebuild" for full rebuild or "Build" for incremental

my $Rebuild = 'Rebuild'; 

#----------------------------------------------------------------------------
# Tool Paths
#----------------------------------------------------------------------------
my $MSBuild  = "MSBuild.exe";
#----------------------------------------------------------------------------
# QIKInstaller Paths
#----------------------------------------------------------------------------
my $QikMakeDir = "\"C:\\Program Files (x86)\\Qualcomm\\QIK\\";

#----------------------------------------------------------------------------
# Build directories
#----------------------------------------------------------------------------
my $BuildDir = cwd();
$BuildDir =~ s/\//\\/g; 

my $DriversDir = "$BuildDir\\..";
my $TargetDir  =  $BuildDir . "\\target";
my $DevEnvOutput = $BuildDir . "\\devEnvOutput.txt";
my $InstallDir = "$BuildDir\\..\\installer";
my $WHQL = "";

#----------------------------------------------------------------------------
# Get the current time and date to be used in the output log filename
#----------------------------------------------------------------------------
my $BuildTime = localtime();
$_ = $BuildTime;

my @words = split(/\s+/);
my $date = "$words[1]$words[2]$words[4]_$words[3]";
$date =~ s/://g;           # remove ':'

# Open the output log file
my $outputlog = "buildQikInstaller_$date.log";
open( LOG , ">$outputlog") || die ("Couldn't open $outputlog : $!");
LOG->autoflush(1);         # no buffering of output

# Parse out arguments
my $RC = ParseArguments();
if ($RC == 0)
{
   close( LOG );
   exit( 1 );
}

#----------------------------------------------------------------------------
# Fire up Driver build 
#----------------------------------------------------------------------------
TimeLog "Beginning version updates and building QIK package...\n";
 
BuildScript(); 
close(LOG);

#----------------------------------------------------------------------------
# Subroutine TRACE
#----------------------------------------------------------------------------

sub TRACE 
{
   foreach( @_)
   {
      print;      # print the entry
      print LOG;  # print the entry to the logfile
   }
}

#----------------------------------------------------------------------------
# Subroutine TimeLog
#----------------------------------------------------------------------------

sub TimeLog 
{
   my($Message) = @_;
   my $date = localtime;
   
   TRACE "\n... $date ...\n";
   TRACE "--------------------------------\n";
   TRACE "$Message\n";
}


#----------------------------------------------------------------------------
# Subroutine Run
#----------------------------------------------------------------------------

# Run a command, optionally piping a string into it on stdin.
# Returns whatever the command printed to stdout.  The whole thing is
# optionally logged.  NOTE that stderr is not redirected.

sub Run
{
   my ($syscall, $stuff_to_pipe_in) = @_;
   my $result;

   print "     Stuff to pipe: $stuff_to_pipe_in\n" if $stuff_to_pipe_in;

   if(defined($stuff_to_pipe_in)) 
   {
      # Use a temporary file because not all systems implement pipes
      open(TEMPFILE,">pipeto") or die "can't open pipeto: $!\n";
      print TEMPFILE $stuff_to_pipe_in;
      close(TEMPFILE);
      $result = `$syscall <pipeto`;
      unlink("pipeto");
   } 
   else 
   {
      $result = system($syscall);
   }

  # append to a file - that way if the converter dies the file will
  # be up to date, and this mechanism doesn't rely on an open filehandle
  TRACE "\n\nCommand: $syscall";
  if ($syscall =~ /sync/) {
     TRACE "     Done\n";
  }
  else
  {
     TRACE "\n$result";
  }
  return $result;
}

#----------------------------------------------------------------------------
# Process the arguments 
#----------------------------------------------------------------------------
sub ParseArguments
{
   # Assume failure
   my $RC = 0;   

   if (defined( $ARGV[0] ))
   {      
      if ($ARGV[0] =~ m/whql/i)
      {
         $WHQL = $ARGV[0];
      }
   }
      
   $RC = 1;
   return $RC;
}


#----------------------------------------------------------------------------
# Subroutine ExitScript
#----------------------------------------------------------------------------
sub ExitScript 
{
   my $Status = shift @_;
   TimeLog "Exiting script due to failure.  Status: $Status\n";
   exit( $Status );
}

sub BuildVSProject
{
   my $Path = $_[0];
   my $Config = $_[1];
   my $BuildType = $_[2];
   my $Arch = $_[3];

   if ($BuildType eq "fre")
   {
      $Config = $Config."Release";
   } 
   else
   {
      $Config = $Config."Debug";
   }

   # Build the Project.
   unlink( $DevEnvOutput );
   my $BuildCommand;
   $BuildCommand = "$MSBuild $Path /t:$Rebuild /p:Configuration=\"$Config\" /p:Platform=$Arch /l:FileLogger,Microsoft.Build.Engine;logfile=$DevEnvOutput";
#   Run( qq( $BuildCommand ) );
   TRACE "$Path -- $Config -- $Arch.\n";
   my $result1;
   $result1 = `$BuildCommand`;
   TRACE "\n$result1"; 
   
   if ($? != 0)
   {
      TRACE "Error Building $Config for $Arch $Path. Correct Problems and Try Again.\n";
      ExitScript( 1 );
   }
   
   open( IN, "$DevEnvOutput" );
   chomp( my @lines = <IN> );
   close( IN );
   foreach (@lines)
   {
      if (/fatal error/i)
      {
         TRACE "$_\n";
         TRACE "Error Building $Config for $Arch $Path. Correct Problems and Try Again.\n";
         ExitScript( 1 );
      }
   }
}
sub BuildScript
{
   BuildVSProject( "$InstallDir\\DriverInstaller64\\DriverInstaller64.vcxproj", "", "fre", "Win32");
   BuildVSProject( "$InstallDir\\Qdclr\\Qdclr.vcxproj", "", "fre", "Win32");
   BuildVSProject( "$InstallDir\\Qdclr\\Qdclr.vcxproj", "", "fre", "x64");
   BuildVSProject( "$InstallDir\\Qdclr\\Qdclr.vcxproj", "", "fre", "ARM");
   BuildVSProject( "$InstallDir\\Qdclr\\Qdclr.vcxproj", "", "fre", "ARM64");
   BuildVSProject( "$InstallDir\\QiKInstaller\\QiKInstaller.vcxproj", "", "fre", "Win32");
   
   my $packageVersion = "";
   my $file = "$DriversDir\\qcversion.h";   
   open my $fh, "<", $file or die $!;
   while (<$fh>) {          
    if (/^#define +QIK_PACKAGE_VERSION +(\S+)/) {
	$packageVersion = $1;
	print "Package Version: $packageVersion\n";
	}
    if (/^#define +QIK_INSTALLER_VERSION +(\S+)/) {
	$QikMakeDir = $QikMakeDir.$1;
	print "QIK make dir :$QikMakeDir\n";
	}        
   }
   close $fh;
   
   Run(qq($QikMakeDir\\QIKEditor.exe\" CONVERT "$InstallDir\\QiKInstaller\\Qualcomm_Libusb_Driver.QIKproj.xml\" -output $InstallDir\\QiKInstaller\\ )); 

   Run(qq($QikMakeDir\\QIKMake.exe\" CREATE "$InstallDir\\QiKInstaller\\Qualcomm_Libusb_Driver.QIKproj\" -version $packageVersion -output $InstallDir\\QiKInstaller\\ -sfx)); 
}