#!/usr/bin/env bash
# Airpods.sh
# Output connected Airpods battery levels via CLI

#BT_DEFAULTS=$(defaults read /Library/Preferences/com.apple.Bluetooth)
SYS_PROFILE=$(system_profiler SPBluetoothDataType 2>/dev/null)
MAC_ADDR=$(grep -b2 "Minor Type: "<<<"${SYS_PROFILE}"|awk '/Address/{print $3}')

regex_connected="(Connected:.+)"

if [[ $SYS_PROFILE =~ $regex_connected ]]
then

#this regex won't work because of PRCE not working with some bash version (Connected:.Yes).(Vendor ID:.0x004C.)(Product ID:.*(Case.+%).+(Firmware Version:.[A-Z-a-z-0-9]+))
patwithCase="(.+).(Vendor ID:.0x004C.)(Product ID.*(Case.+%))"
patwithoutCase="(.+).(Vendor ID:.0x004C.)(Product ID.*.)"
replace="?"

comp=$(echo ${SYS_PROFILE}  | sed "s/Address:/$replace/g")
set -f
IFS='?'
ary=($comp)
for key in "${!ary[@]}";
do
d=$(echo "${ary[$key]}")
data=""
macAddress=""
connectedStatus=""
vendorID=""
batteryLevel=""
firmwareVersion=""

if [[ $d =~ $patwithCase ]]
then
macAddress=$( echo "${BASH_REMATCH[1]}" | sed 's/ *$//g')
connectedStatus="${BASH_REMATCH[2]}"
vendorID="${BASH_REMATCH[3]}"
data="${BASH_REMATCH[4]}"
firmwareVersion=$(echo ${BASH_REMATCH[6]} | awk '{print $3}')

batterylevelregex="Case Battery Level: (.+%) Left Battery Level: (.+%) Right Battery Level: (.+%)"
batterySingleRegex="(BatteryPercentSingle) = ([0-9]+)"
if [[ $data =~ $batterylevelregex ]]
then
caseBattery="${BASH_REMATCH[1]}"
leftBattery="${BASH_REMATCH[2]}"
rightBattery="${BASH_REMATCH[3]}"
batteryLevel="${caseBattery} ${leftBattery} ${rightBattery}"
if [ -z "$batteryLevel" ]
then
echo ""
else
echo $macAddress"@@""$batteryLevel"
fi
elif [[ $data =~ $batterySingleRegex ]]
then
#IN PROGRESS - AIRPODS MAX (TO VERIFY)
batteryLevel=$macAddress"@@"${BASH_REMATCH[2]}
echo $batteryLevel
fi
elif [[ $d =~ $patwithoutCase ]]
then
macAddress=$( echo "${BASH_REMATCH[1]}" | sed 's/ *$//g')
vendorID="${BASH_REMATCH[2]}"
data="${BASH_REMATCH[3]}"
firmwareVersion=$(echo ${BASH_REMATCH[6]} | awk '{print $3}')
batterylevelregex="Left Battery Level: (.+%) Right Battery Level: (.+%)"

if [[ $data =~ $batterylevelregex ]]
then
caseBattery="-1"
leftBattery="${BASH_REMATCH[1]}"
rightBattery="${BASH_REMATCH[2]}"
batteryLevel="${caseBattery} ${leftBattery} ${rightBattery}"
if [ -z "$batteryLevel" ]
then
echo ""
else
echo $macAddress"@@""$batteryLevel"
fi
fi
fi
done
else
echo "nc"
fi
exit 0
