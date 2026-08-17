#!/bin/bash
echo "1"
ls logs_practice
ls logs_practice/*.csv|wc -l
echo "2"
wc -l logs_practice/*.csv
echo "3"
cut -d ',' -f2,3 logs_practice/sales_jan.csv
echo "4"
awk -F ',' '$5=="Active" && $4>40000 {print $0 }' logs_practice/*.csv
echo "5"
awk -F ',' 'tolower($2) ~/^[aeiou]/ {print $2}' logs_practice/*.csv
echo "7"
cut -d "," -f3 logs_practice/*.csv | sort -u |wc -l



