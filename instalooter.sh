#!/bin/sh
#
# Helper script for running instaLooter (sudo pip install instaLooter).  It started as a
# for loop, and has become useful enough and generic enough for anyone to use if they
# wish.
#
# ---------------------------------------------------------------------------------------
# ISC License
# 
# Copyright (c) Stephen Horner 2017 (bitmarauder@tuta.io) PGP: 7FCEDB5DBE493F18
# 
# Permission to use, copy, modify, and/or distribute this software for any purpose with or
# without fee is hereby granted, provided that the above copyright notice and this
# permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO
# THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER
# IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
# CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# ---------------------------------------------------------------------------------------


# This is the list of accounts to be downloaded. It is newline delimited, so leave
# the formatting fo the list like this example:
#
ACCOUNTS="
coolcars
goodeats
foobarbaz
boognish
"


# Everything is done in ./ but could be set to something else if needed.
#
ROOTDIR=$('pwd')

# The default is "" as in this script can be run without credentials if need be.
#
CREDENTIALS="name:passwd"

# Root directory for our loot.
#
LOOTDIR="$ROOTDIR/loot/"

# Every time this script is run it will try to save stdout and stderr to this file.
# If this file exists as it should then it will be renamed to $LOOT_LOG-$(datestring).log
# And then this sessions output will be saved to a newly created $LOOT_LOG for this session.
#
LOOT_LOG="loot.log"


raid_loot() {

	# Account name as in http://www.instagram/accountname
	_name_t="$1"

	# 0 means the acct is new 1 means we've downloaded it before so just update.
	_newid=0 

	# Does this ID have a directory? if not make it and set it as a new ID 
	if [ ! -d $LOOTDIR/$_name_t ] ; then 
		mkdir -p "$LOOTDIR/$_name_t"
		_newid="yes"
	else
		# Since the dir exists set as not a new ID so we can update only new media.
		_newid="no"
		itemsindir="$(ls -AlFG "$LOOTDIR/$_name_t" | wc -l)" >> $LOOT_LOG 2>&1
		echo "$LOOTDIR/$_name_t already exists, not doing mkdir." >> $LOOT_LOG 2>&1
	fi

	echo "Raiding account $_name_t for all their loot:" >> $LOOT_LOG 2>&1


	# TODO is -m broken? and what's the actual -n limit?

	# Download only new content since we have this ID
	if [ -n $CREDENTIALS ] && [ $itemsindir -ge 3 ] ; then 
		nohup instaLooter -q -N -v -n 6000 -j 12 -c "$CREDENTIALS" "$_name_t" "$LOOTDIR/$_name_t" >> $LOOT_LOG 2>&1

	# Download all content since this is a new ID
	elif [ $_newid == "yes" ] ; then
		nohup instaLooter -q -v -n 6000 -j 12 -c "$CREDENTIALS" "$_name_t" "$LOOTDIR/$_name_t" >> $LOOT_LOG 2>&1

	# Download as anonymous user
	else	
		nohup instaLooter -q -v -n 6000 -j 12 "$_name_t" "$LOOTDIR/$_name_t" >> $LOOT_LOG 2>&1
	fi
	# I think we're being limited... but something goes haywire after a few accounts are downloaded. ???
}


raid_loot_list() {
	# Logfile cruft
	if [ -f "$ROOTDIR/$LOOT_LOG" ] ;  then
		mv "$ROOTDIR/$LOOT_LOG" "$ROOTDIR/$LOOT_LOG-$(date "+%Y%m%d%H%M").log"
		touch "$ROOTDIR/$LOOT_LOG"
	else 
		touch "$ROOTDIR/$LOOT_LOG"
	fi
	
	# MAIN 
	# TODO is this the best way to loop over this list?
	for name in $ACCOUNTS ; do
		# Is IG limiting us? is that why it errors sometiemes? 
		# Or is it a timeout that instaLooter can't handle?
		sleep 5 && raid_loot "$name" 
	done
	sync
}

raid_loot_list

return 0

# EOF
