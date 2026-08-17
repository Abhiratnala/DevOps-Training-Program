#!/bin/bash
name="Abhignya Ratnala"
roll_no=6
date=`date`
echo -n "enter a "
read a
echo -n "enter b "
read b
r1=$((a+b))
r2=$((a-b))
r3=$((a*b))
r4=$((b/a))
r5=$((b%a))
echo "Addition: $r1"
echo "Substraction: $r2"
echo "Multiplication: $r3"
echo "Division: $r4"
echo "Modulus: $r5"
echo "String Variable: $name"
echo "Integer Variable: $roll_no"
echo "Current Date: $date"
echo "First Number: $a"
echo "Second Number: $b"

