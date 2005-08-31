#!/bin/sh
#
#	setup 4.1 - install a MINIX distribution	
#
# Changes:
#    Aug     2005   robustness checks and beautifications  (Jorrit N. Herder)
#    Jul     2005   extended with autopart and networking  (Ben J. Gras)
#    Dec 20, 1994   created  (Kees J. Bot)
#						

LOCALRC=/usr/etc/rc.local
MYLOCALRC=/mnt/etc/rc.local

PATH=/bin:/usr/bin
export PATH


usage()
{
    cat >&2 <<'EOF'
Usage:	setup		# Install a skeleton system on the hard disk.
	setup /usr	# Install the rest of the system (binaries or sources).

	# To install from other things then floppies:

	urlget http://... | setup /usr		# Read from a web site.
	urlget ftp://... | setup /usr		# Read from an FTP site.
	mtools copy c0d0p0:... - | setup /usr	# Read from the C: drive.
	dosread c0d0p0 ... | setup /usr		# Likewise if no mtools.
EOF
    exit 1
}

warn() 
{
  echo -e "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b ! $1"
}

# No options.
while getopts '' opt; do usage; done
shift `expr $OPTIND - 1`

if [ "$USER" != root ]
then	echo "Please run setup as root."
	exit 1
fi

# Find out what we are running from.
exec 9<&0 </etc/mtab			# Mounted file table.
read thisroot rest			# Current root (/dev/ram or /dev/fd?)
read fdusr rest				# USR (/dev/fd? or /dev/fd?p2)
exec 0<&9 9<&-

# What do we know about ROOT?
case $thisroot:$fdusr in
/dev/ram:/dev/fd0p2)	fdroot=/dev/fd0		# Combined ROOT+USR in drive 0
			;;
/dev/ram:/dev/fd1p2)	fdroot=/dev/fd1		# Combined ROOT+USR in drive 1
			;;
/dev/ram:/dev/fd*)	fdroot=unknown		# ROOT is some other floppy
			;;
/dev/fd*:/dev/fd*)	fdroot=$thisroot	# ROOT is mounted directly
			;;
*)			fdroot=$thisroot	# ?
esac

echo -n "
Welcome to the MINIX setup script.  This script will guide you in setting up
MINIX on your machine.  Please consult the manual for detailed instructions.

Note 1: If the screen blanks, hit CTRL+F3 to select \"software scrolling\".
Note 2: If things go wrong then hit CTRL+C to abort and start over.
Note 3: Default answers, like [y], can simply be chosen by hitting ENTER.
Note 4: If you see a colon (:) then you should hit ENTER to continue.
:"
read ret

# begin Step 1
echo ""
echo " --- Step 1: Select keyboard type --------------------------------------"
echo ""

    echo "What type of keyboard do you have?  You can choose one of:"
    echo ""
    ls -C /usr/lib/keymaps | sed -e 's/\.map//g' -e 's/^/    /'
    echo ""
step1=""
while [ "$step1" != ok ]
do
    echo -n "Keyboard type? [us-std] "; read keymap
    test -n "$keymap" || keymap=us-std
    if loadkeys "/usr/lib/keymaps/$keymap.map" 2>/dev/null 
    then step1=ok 
    else warn "invalid keyboard"
    fi
done
# end Step 1


# begin Step 2
step2=""
while [ "$step2" != ok ]
do
	echo ""
	echo " --- Step 2: Create a partition for MINIX 3, Or Reinstall ------------"
	echo ""

    echo "Now you need to create a MINIX 3 partition on your hard disk."
    echo "You can also select one that's already there."
    echo " "
    echo "If you have an existing installation, 'reinstall'ing will let you"
    echo "keep your current partitioning and subpartitioning, and overwrite"
    echo "everything except your s3 subpartition (/home)."
    echo " "
    echo "Unless you are an expert, you are advised to use the automated"
    echo "step-by-step help in setting up."
    echo ""
    ok=""
    while [ "$ok" = "" ]
    do
	    echo "Press ENTER for automatic mode, or type 'expert', or"
	    echo -n "type 'reinstall': "
	    read mode
	    if [ -z "$mode" ]; then auto="1"; ok="yes"; fi 
	    if [ "$mode" = expert ]; then auto=""; ok="yes"; fi
	    if [ "$mode" = reinstall ]; then auto="r"; ok="yes"; fi
	    if [ "$ok" != yes ]; then warn "try again"; fi 
    done

	primary=

	if [ -z "$auto" ]
	then
		# Expert mode
		echo -n "
MINIX needs one primary partition of about 250 MB for a full install.
The maximum fill system currently supported is 4 GB.

If there is no free space on your disk then you have to choose an option:
   (1) Delete one or more partitions
   (2) Allocate an existing partition to MINIX 3
   (3) Exit setup and shrink a partition using a different OS

To make this partition you will be put in the editor \"part\".  Follow the
advice under the '!' key to make a new partition of type MINIX.  Do not
touch an existing partition unless you know precisely what you are doing!
Please note the name of the partition (e.g. c0d0p1, c0d1p3, c1d1p0) you
make.  (See the devices section in usage(8) on MINIX device names.)
:"
		read ret

		while [ -z "$primary" ]
		do
		    part || exit

		    echo -n "
Please finish the name of the primary partition you have created:
(Just type ENTER if you want to rerun \"part\")                   /dev/"
		    read primary
		done
		echo ""
		echo "This is the point of no return.  You have selected to install MINIX"
		echo "on partition /dev/$primary.  Please confirm that you want to use this"
		echo "selection to install MINIX."
		echo ""
		confirmation=""
		while [ -z "$confirmation" -o "$confirmation" != yes -a "$confirmation" != no ]
		do
			echo -n "Are you sure you want to continue? Please enter 'yes' or 'no': "
			read confirmation
			if [ "$confirmation" = yes ]; then step2=ok; fi
		done
		biosdrivename="Actual BIOS device name unknown, due to expert mode."
	else
		if [ "$auto" = "1" ]
		then
			# Automatic mode
			PF="/tmp/pf"
			if autopart -f$PF
			then	if [ -s "$PF" ]
				then
					set `cat $PF`
					bd="$1"
					bdn="$2"
					biosdrivename="Probably, the right command is \"boot $bdn\"."
					if [ -b "/dev/$bd" ]
					then	primary="$bd"
					else	echo "Funny device $bd from autopart."
					fi
				else
					echo "Didn't find output from autopart."
				fi 
			else	echo "Autopart tool failed. Trying again."
			fi

			# Reset at retries and timeouts in case autopart left
			# them messy.
			atnormalize

			if [ -n "$primary" ]; then step2=ok; fi
		else
			# Reinstall mode
			primary=""

			while [ -z "$primary" ]
			do
			    echo -n "
Please finish the name of the primary partition you have a MINIX install on:
/dev/"
			    read primary
			done
			echo ""
			echo "This is the point of no return.  You have selected to reinstall MINIX"
			echo "on partition /dev/$primary.  Please confirm that you want to use this"
			echo "selection to reinstall MINIX. This will wipe out your s0 (root) and"
			echo "s2 (/usr) filesystems."
			echo ""
			confirmation=""
			while [ -z "$confirmation" -o "$confirmation" != yes -a "$confirmation" != no ]
			do
				echo -n "Are you sure you want to continue? Please enter 'yes' or 'no': "
				read confirmation
				if [ "$confirmation" = yes ]; then step2=ok; fi
			done
			biosdrivename="Actual BIOS device name unknown, due to reinstallation."
		fi
	fi
done	# while step2 != ok
# end Step 2

if [ ! "$auto" = "r" ]
then
	# begin Step 3
	echo ""
	echo " --- Step 3: Select your Ethernet chip ---------------------------------"
	echo ""
	
	# Ask user about networking
	echo "MINIX 3 currently supports the following Ethernet cards. Please choose: "
	    echo ""
	    echo "0. No Ethernet card (no networking)"
	    echo "1. Intel Pro/100"
	    echo "2. Realtek 8139 based card"
	    echo "3. Realtek 8029 based card (emulated by Qemu)"
	    echo "4. NE2000, 3com 503 or WD based card (emulated by Bochs)"
	    echo "5. 3Com 501 or 3Com 509 based card"
	    echo "6. Different Ethernet card (no networking)"
	    echo ""
	    echo "You can always change your mind after the setup."
	    echo ""
	step3=""
	while [ "$step3" != ok ]
	do
	    eth=""
	    echo -n "Ethernet card? [0] "; read eth
	    test -z $eth && eth=0
	    driver=""
	    driverargs=""
	    case "$eth" in
	        0) step3="ok"; ;;    
		1) step3="ok";	driver=fxp;      ;;
		2) step3="ok";	driver=rtl8139;  ;;
		3) step3="ok";	driver=dp8390;   driverargs="dp8390_arg='DPETH0=pci'";	;;
		4) step3="ok";	driver=dp8390;   driverargs="dp8390_arg='DPETH0=240:9'"; 
		   echo ""
	           echo "Note: After installing, edit $LOCALRC to the right configuration."
	           echo " chose option 4, the defaults for emulation by Bochs have been set."
			;;
		5) step3="ok";	driver=dpeth;    driverargs="#dpeth_arg='DPETH0=port:irq:memory'";
		   echo ""
	           echo "Note: After installing, edit $LOCALRC to the right configuration."
			;;
	        6) step3="ok"; ;;    
	        *) warn "choose a number"
	    esac
	done
	# end Step 3
fi

defmb=200

if [ ! "$auto" = r ]
then	homesize=""
	while [ -z "$homesize" ]
	do
		echo ""
		echo -n "How big do you want your /home to be, in MB? [$defmb] "
		read homesize
		if [ "$homesize" = "" ] ; then homesize=$defmb; fi
		echo -n "$homesize MB Ok? [Y] "
		read ok
		[ "$ok" = Y -o "$ok" = y -o "$ok" = "" ] || homesize=""
		echo ""
	done
	# Homesize in sectors
	homemb="$homesize MB"
	homesize="`expr $homesize '*' 1024 '*' 2`"
else
	# Homesize unchanged (reinstall)
	homesize=exist
	homemb="current size"
fi

root=${primary}s0
home=${primary}s1
usr=${primary}s2
umount /dev/$root 2>/dev/null && echo "Unmounted $root for you."
umount /dev/$home 2>/dev/null && echo "Unmounted $home for you."
umount /dev/$usr 2>/dev/null && echo "Unmounted $usr for you."

blockdefault=4

if [ ! "$auto" = "r" ]
then
	echo ""
	echo " --- Step 4: Select a block size ---------------------------------------"
	echo ""
	
	echo "The maximum (and default) file system block size is $blockdefault KB."
	echo "For a small disk or small RAM you may want 1 or 2 KB blocks."
	echo ""
	
	while [ -z "$blocksize" ]
	do	
		echo -n "Block size in kilobytes? [$blockdefault] "; read blocksize
		test -z "$blocksize" && blocksize=$blockdefault
		if [ "$blocksize" -ne 1 -a "$blocksize" -ne 2 -a "$blocksize" -ne $blockdefault ]
		then	
			warn "1, 2 or 4 please"
			blocksize=""
		fi
	done
else
	blocksize=$blockdefault
fi

blocksizebytes="`expr $blocksize '*' 1024`"

echo "
You have selected to (re)install MINIX in the partition /dev/$primary.
The following subpartitions are now being created on /dev/$primary:

    Root subpartition:	/dev/$root	16 MB
    /home subpartition:	/dev/$home	$homemb
    /usr subpartition:	/dev/$usr	rest of $primary
"
					# Secondary master bootstrap.
installboot -m /dev/$primary /usr/mdec/masterboot >/dev/null || exit
					# Partition the primary.
partition /dev/$primary 1 81:32768* 81:$homesize 81:0+ > /dev/null || exit

echo "Creating /dev/$root .."
mkfs -B $blocksizebytes /dev/$root || exit

if [ ! "$auto" = r ]
then	echo "Creating /dev/$home .."
	mkfs -B $blocksizebytes /dev/$home || exit
fi

echo "Creating /dev/$usr .."
mkfs -B $blocksizebytes /dev/$usr || exit

echo ""
echo " --- Step 5: Wait for bad block detection ------------------------------"
echo ""
echo "Scanning disk for bad blocks.  Hit CTRL+C to stop the scan if you are"
echo "sure that there can not be any bad blocks.  Otherwise just wait."

trap ': nothing;echo' 2
echo ""
echo "Scanning /dev/$root for bad blocks:"
readall -b /dev/$root | sh

echo "Scanning /dev/$home for bad blocks:"
readall -b /dev/$home | sh
trap 2

echo ""
echo "Scanning /dev/$usr for bad blocks:"
readall -b /dev/$usr | sh
trap 2

echo ""
echo " --- Step 6: Wait for files to be copied -------------------------------"
echo ""
echo "This is the final step of the MINIX setup.  All files will be now be"
echo "copied to your hard disk.  This may take a while."
echo ""

mount /dev/$usr /mnt >/dev/null || exit		# Mount the intended /usr.

files="`find /usr | wc -l`"
cpdir -v /usr /mnt | progressbar "$files" || exit	# Copy the usr floppy.


					# Set inet.conf to correct driver
if [ -n "$driver" ]
then	echo "$driverargs" >$MYLOCALRC
	disable=""
else	disable="disable=inet;"
fi

umount /dev/$usr >/dev/null || exit		# Unmount the intended /usr.
mount /dev/$root /mnt >/dev/null || exit

# Running from the installation CD.
files="`find / -xdev | wc -l`"
cpdir -vx / /mnt | progressbar "$files" || exit	

if [ -n "$driver" ]
then	echo "eth0 $driver 0 { default; };" >/mnt/etc/inet.conf
fi

# CD remnants that aren't for the installed system
rm /mnt/etc/issue /mnt/CD 2>/dev/null
					# Change /etc/fstab. (No swap.)
					# ${swap:+swap=/dev/$swap}
echo >/mnt/etc/fstab "\
# Poor man's File System Table.

root=/dev/$root
usr=/dev/$usr
home=/dev/$home"

					# National keyboard map.
test -n "$keymap" && cp -p "/usr/lib/keymaps/$keymap.map" /mnt/etc/keymap

umount /dev/$root >/dev/null || exit	# Unmount the new root.
mount /dev/$usr /mnt >/dev/null || exit

if [ ! "$auto" = "r" ]
then
	# Make bootable.
	installboot -d /dev/$root /usr/mdec/bootblock /boot/boot >/dev/null || exit
	edparams /dev/$root "rootdev=$root; ramimagedev=$root; $disable; minix(=,Start MINIX 3) { unset image; boot; }; smallminix(+,Start Small MINIX 3) { image=/boot/image_small; ramsize=0; boot; }; main() { echo By default, MINIX 3 will automatically load in 3 seconds.; echo Press ESC to enter the monitor for special configuration.; trap 3000 boot; menu; }; save" || exit
	pfile="/mnt/src/tools/fdbootparams"
	# echo "Remembering boot parameters in ${pfile}."
	echo "rootdev=$root; ramimagedev=$root; $disable; save" >$pfile || exit
	umount /dev/$usr
fi

sync

bios="`echo $primary | sed 's/d./dX/g'`"

echo "
Please type 'shutdown' to exit MINIX 3 and enter the boot monitor. At
the boot monitor prompt, type 'boot $bios', where X is the bios drive
number of the drive you installed on, to try your new MINIX system.
$biosdrivename

This ends the MINIX setup script.  After booting your newly set up system,
you can run the test suites as indicated in the setup manual.  You also 
may want to take care of local configuration, such as securing your system
with a password.  Please consult the usage manual for more information. 

"

