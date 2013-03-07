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
p="$p&export_type=server&export_method=quick&quick_or_custom=custom&output_format=sendit&filename_template=__SERVER__&remember_template=on&charset_of_file=utf-8&what=sql&codegen_structure_or_data=data&codegen_format=0&csv_separator=%2C&csv_enclosed=%22&csv_escaped=%22&csv_terminated=AUTO&csv_null=NULL&csv_structure_or_data=data&excel_null=NULL&excel_edition=win&excel_structure_or_data=data&htmlword_structure_or_data=structure_and_data&htmlword_null=NULL&json_structure_or_data=data&latex_caption=something&latex_structure_or_data=structure_and_data&latex_structure_caption=Structure+of+table+%40TABLE%40&latex_structure_continued_caption=Structure+of+table+%40TABLE%40+%28continued%29&latex_structure_label=tab%3A%40TABLE%40-structure&latex_comments=something&latex_columns=something&latex_data_caption=Content+of+table+%40TABLE%40&latex_data_continued_caption=Content+of+table+%40TABLE%40+%28continued%29&latex_data_label=tab%3A%40TABLE%40-data&latex_null=%5Ctextit%7BNULL%7D&mediawiki_structure_or_data=data&ods_null=NULL&ods_structure_or_data=data&odt_structure_or_data=structure_and_data&odt_comments=something&odt_columns=something&odt_null=NULL&pdf_report_title=&pdf_structure_or_data=data&php_array_structure_or_data=data&sql_include_comments=something&sql_header_comment=&sql_compatibility=NONE&sql_structure_or_data=structure_and_data&sql_procedure_function=something&sql_create_table_statements=something&sql_if_not_exists=something&sql_auto_increment=something&sql_backquotes=something&sql_type=INSERT&sql_insert_syntax=both&sql_max_query_size=50000&sql_hex_for_blob=something&sql_utc_time=something&texytext_structure_or_data=structure_and_data&texytext_null=NULL&yaml_structure_or_data=data"

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
	FILENAME=$OUPUT_DIR/"$DATABASE".$(date +%Y%m%d.%H%M)."$(cat $CURLHEADERS | grep "Content-Disposition: attachment" | sed "s/.*filename=\"//" | sed "s/\".*//")"

	mv $EXPORT $FILENAME
	echo "--> Saved $FILENAME"	
else
	echo "--> no attachment"
fi
