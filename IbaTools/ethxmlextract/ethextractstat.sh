#!/bin/bash
# BEGIN_ICS_COPYRIGHT8 ****************************************
#
# Copyright (c) 2015-2020, Intel Corporation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Intel Corporation nor the names of its contributors
#       may be used to endorse or promote products derived from this software
#       without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# END_ICS_COPYRIGHT8   ****************************************

# [ICS VERSION STRING: unknown]

# Run ethreport -o errors with topology XML, then:
#   Extract values (including port statistics) for both ports of each link
#   Remove redundant information for each link and combine link port information

tempfile="$(mktemp)"
trap "rm -f $tempfile; exit 1" SIGHUP SIGTERM SIGINT
trap "rm -f $tempfile" EXIT

## Local functions:

# Usage()
#
# Description:
#   Output information about program usage and parameters
#
# Inputs:
#   none
#
# Outputs:
#   Information about program usage and parameters



usage()
{
    echo "Usage:  ${cmd} topology_file [ethreport options]" >&2
    echo "       or  ${cmd} --help" >&2
    echo "   --help - produce full help text" >&2
    echo "   [ethreport options] - options will be passed to ethreport." >&2
    exit 2
}

Usage_full()
{
	echo >&2
	echo "Usage: ${cmd} topology_file [ethreport options]" >&2
	echo "       or  ${cmd} --help" >&2
	echo "   --help - produce full help text" >&2
	echo "   [ethreport options] - options will be passed to ethreport." >&2
	echo >&2
	echo "${cmd} is a front end to the ethreport and ethxmlextract tools that" >&2
	echo "performs an error analysis of a fabric and provides augmented information" >&2
	echo "from a topology file. Report provides cable information as well" >&2
	echo "as symbol error count." >&2
	echo "The output is in a CSV format suitable for importing into a spreadsheet or" >&2
	echo "parsed by other scripts." >&2
	echo >&2
	echo "for example:" >&2
	echo "	${cmd} topology_file"
	echo >&2
	echo "	${cmd} topology_file -c my_ethmon.conf"
	echo >&2
	echo "See the man page for \"ethreport\" for the full set of options." >&2
	echo "By design, the tool ignores \"-o/--output\" report option." >&2
	echo >&2

}

## Main function:

cmd=`basename $0`
if [ x"$1" = "x--help" ]
then
	Usage_full
	exit 0
fi

if [[ $# -lt 1 || "$1" == -* ]]
then
    usage
fi

# NOTE: ethreport -o errors generates XML output of this general form:
#  <Link>
#     <Rate>....
#     <LinkDetails>....
#     <Cable>
#       ... cable information from topology.xml
#     </Cable>
#     <Port>
#       .. information about 1st port excluding its CableInfo
#     </Port>
#     <Port>
#       .. information about 2nd port excluding its CableInfo
#     </Port>
#     <CableInfo>
#       .. information about the CableInfo for the cable between the two ports
#     </CableInfo>
#  </Link>
  # ethxmlextract produces the following CSV format on each line:
  #    1 Link ID (CSV 1) LinkID
  #    2 Link values (CSV 2-3) (Rate, LinkDetails)
  #    3 Cable values (CSV 4-6) (CableLength, CableLabel, CableDetails)
  #    4 Port values (CSV 7-10) (NodeDesc, PortNum, PortId, LinkQualityIndicator)
  # due to the nesting of tags, ethxmlextract will output the following
  #    All lines have LinkID and Rate and one set of Cable values or Port Values

# Combine 2 ports for each link onto 1 line, removing redundant Link and Cable values
link1=0
link2=0
printHeader=1
curLinkID=""
prevLinkID=""
RateStr=""
LinkDetailsStr=""
CableValuesStr=";;"
Port1ValuesStr=";;"
Port2ValuesStr=";;"

header="Rate;LinkDetails;CableLength;CableLabel;CableDetails;Port.NodeDesc;Port.PortNum;Port.PortId;Port.NodeDesc;Port.PortNum;Port.PortId"


/usr/sbin/ethreport -x -Q -d 10 -o errors -T "$@" > $tempfile
if [ ! -s $tempfile ]
then
	echo "ethextractstat: Unable to get errors report" >&2
	Usage_full
	exit 1
fi

while read line
do

  curLinkID=`echo $line | cut -d \; -f 1`

  # When Link:ID changes, print previous link and start new one
  if [ "$curLinkID" != "$prevLinkID" ]
  then
    # Display header first time
    if [ $printHeader -eq 1 ]
    then
        echo $header
        printHeader=0
    fi

    # Display the previous link before starting this new one
    if [ "$prevLinkID" != "" ]
    then
        echo $RateStr";"$LinkDetailsStr";"$CableValuesStr";"$Port1ValuesStr";"$Port2ValuesStr
    fi

    # Reset for the next set of data
    link1=0
    link2=0
    RateStr=""
    LinkDetailsStr=""
    CableValuesStr=";;"
    Port1ValuesStr=";;"
    Port2ValuesStr=";;"
    prevLinkID=$curLinkID
  fi

  if [ "$RateStr" == "" ]
  then
    RateStr=`echo $line | cut -d \; -f 2`
  fi

  if [ "$LinkDetailsStr" == "" ]
  then
    LinkDetailsStr=`echo $line | cut -d \; -f 3`
  fi

  if [ "$CableValuesStr" == ";;" ]
  then
    CableValuesStr=`echo $line | cut -d \; -f 4-6`
  fi

  if [ $link1 -eq 0 ]
  then
    if [ "$Port1ValuesStr" == ";;" ]
    then
      Port1ValuesStr=`echo $line | cut -d \; -f 7-`
    fi
    if [ "$Port1ValuesStr" != ";;" ]
    then
      link1=1
    fi
  elif [ $link2 -eq 0 ]
  then
    if [ "$Port2ValuesStr" == ";;" ]
    then
      Port2ValuesStr=`echo $line | cut -d \; -f 7-`
    fi
    if [ "$Port2ValuesStr" != ";;" ]
    then
      link2=1
    fi
  fi

done < <(cat $tempfile | \
        /usr/sbin/ethxmlextract -H -d \; -e Link:id -e Rate -e LinkDetails -e CableLength \
        -e CableLabel -e CableDetails -e Port.NodeDesc -e Port.PortNum -e Port.PortId)

if [ $printHeader -eq 1 ]
then
  # No links displayed, still print header
  echo $header
fi


# print the last link record
if [ "$prevLinkID" != "" ]
then
  echo $RateStr";"$LinkDetailsStr";"$CableValuesStr";"$Port1ValuesStr";"$Port2ValuesStr
fi

exit 0

