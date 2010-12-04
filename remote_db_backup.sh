#!/bin/bash

function make_temp_file {
	local MAKE_TEMP_CMD
	
	MAKE_TEMP_CMD=$(which tempfile)
	if [ $? -ne 0 ]; then
		MAKE_TEMP_CMD=$(which mktemp)
		
		if [ $? -eq 0 ]; then		
           	MAKE_TEMP_CMD="$MAKE_TEMP_CMD -q /tmp/$(basename $0).XXXXXX"
           if [ $? -ne 0 ]; then
                   echo "$0: Can't create temp file, exiting..."
                   exit 1
           fi
		fi		
	fi
	TMP=$($MAKE_TEMP_CMD)	# return the temp file to the referenced variable $TMP
	if [ $? -ne 0 ]; then
		echo "$0: Can't create temp file, exiting..."
		exit 1
	fi	
}

# Please set the variable below

USERNAME=
PASSWORD=
# https://
PROTOCOL=
# dbadmin.one.com
DOMAIN=
DATABASE=
OUPUT_DIR=/tmp

# 1 = on, 0 = off
COMPRESSION=

# bzip/gzip
METHOD=

###############################################################
#
#	Main Program
#
###############################################################

SERVER="$PROTOCOL$DOMAIN"

if [ ! -d '/tmp' ]; then
	echo Mmm no tmp directory
	exit 1
fi

CURLHEADERS=/tmp/curl_headers
COOKIES=/tmp/cookies
EXPORT=export.php

rm -f $CURLHEADERS
rm -f $COOKIES
rm -f $EXPORT

# create a temporary file
TMP=''
make_temp_file

###############################################################
#
#	Fetch the phpmyadmin cookie
#
###############################################################
curl -s -k -D $CURLHEADERS -L -c $COOKIES --keepalive-time 300 $SERVER/index.php > $TMP

TOKEN=$(grep link $TMP | grep "token.*&amp;" | sed "s/^.*token=//" | sed "s/&amp;.*//")
COOKIE=$(cat $COOKIES | cut -f 6-7 | grep phpMyAdmin | cut -f 2)

p="-d \"phpMyAdmin=$COOKIE"
p="$p&phpMyAdmin=$COOKIE"
p="$p&pma_username=$USERNAME"
p="$p&pma_password=$PASSWORD"
p="$p&server=1"
p="$p&phpMyAdmin=$COOKIE"
p="$p&lang=en-iso-8859-1"
p="$p&convcharset=iso-8859-1"
p="$p&token=$TOKEN\""

###############################################################
#
#	POST of the login form
#
###############################################################

curl -s -S -k -L  -D $CURLHEADERS -b $COOKIES -c $COOKIES $p $SERVER/index.php > $TMP

if [ $? -ne 0 ]; then
	echo "Curl Error on : curl $p -s -k -D $CURLHEADERS -L -c $COOKIES $SERVER/index.php. Check contents of $TMP" >&2
	exit 1
fi
grep -q "HTTP/1.1 200 OK" $CURLHEADERS
if [ $? -ne 0 ]; then
	echo -n "Error : couldn't login to phpMyadmin on $SERVER/index.php" >&2
	grep "HTTP/1.1 " $CURLHEADERS >&2
	exit 1
fi

###############################################################
#
#	Fetch the dump using the cookie/token
#
###############################################################

p="token=$TOKEN"
p="$p&db=$DATABASE"
p="$p&export_type=database&what=sql&csv_separator=%3B&csv_enclosed=%26quot%3B&csv_escaped=%5C&csv_terminated=AUTO&csv_null=NULL&csv_data=&excel_null=NULL&excel_edition=Windows&excel_data=&htmlexcel_null=NULL&htmlexcel_data=&htmlword_structure=something&htmlword_data=something&htmlword_null=NULL&latex_caption=something&latex_structure=something&latex_structure_caption=Structure+of+table+__TABLE__&latex_structure_continued_caption=Structure+of+table+__TABLE__+%28continued%29&latex_structure_label=tab%3A__TABLE__-structure&latex_comments=something&latex_data=something&latex_columns=something&latex_data_caption=Content+of+table+__TABLE__&latex_data_continued_caption=Content+of+table+__TABLE__+%28continued%29&latex_data_label=tab%3A__TABLE__-data&latex_null=%5Ctextit%7BNULL%7D&ods_null=NULL&ods_data=&odt_structure=something&odt_comments=something&odt_data=something&odt_columns=something&odt_null=NULL&pdf_report_title=&pdf_data=1&sql_header_comment=&sql_compatibility=NONE&sql_structure=something&sql_drop=something&sql_auto_increment=something&sql_backquotes=something&sql_data=something&sql_columns=something&sql_extended=something&sql_max_query_size=50000&sql_hex_for_binary=something&sql_type=INSERT&xml_data=&filename_template=__DB__&remember_template=on"

if [ $COMPRESSION -eq 1 ]; then
	if [ $METHOD == 'bzip' ]; then
		p="$p&compression=bzip"
	else
		p="$p&compression=gzip"
	fi
else
    p="$p&asfile=sendit&compression=none"
fi

echo "--> Exporting database ($DATABASE) from $SERVER"

curl -s -S -O -k -D $CURLHEADERS -L -b $COOKIES -d "$p" $SERVER/$EXPORT

grep -q "Content-Disposition: attachment" $CURLHEADERS
if [ $? -eq 0 ]; then
	FILENAME=$OUPUT_DIR/$(date +%Y%m%d.%H%M)."$(cat $CURLHEADERS | grep "Content-Disposition: attachment" | sed "s/.*filename=\"//" | sed "s/\".*//")"

	mv $EXPORT $FILENAME
	echo "--> Saved $FILENAME"	
else
	echo "--> no attachment"
fi
