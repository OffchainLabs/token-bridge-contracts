#!/bin/bash
output_dir="./test/storage"
for CONTRACTNAME in L1ERC20Gateway L1CustomGateway L1ReverseCustomGateway L1WethGateway L2ERC20Gateway L2CustomGateway L2ReverseCustomGateway L2WethGateway L1GatewayRouter L2GatewayRouter StandardArbERC20
do
    echo "Checking storage change of $CONTRACTNAME"
    [ -f "$output_dir/$CONTRACTNAME.dot" ] && mv "$output_dir/$CONTRACTNAME.dot" "$output_dir/$CONTRACTNAME-old.dot"
    yarn sol2uml storage ./ -c "$CONTRACTNAME" -o "$output_dir/$CONTRACTNAME.dot" -f dot
    diff "$output_dir/$CONTRACTNAME-old.dot" "$output_dir/$CONTRACTNAME.dot"
    if [[ $? != "0" ]]
    then
        CHANGED=1
    fi
done
if [[ $CHANGED == 1 ]]
then
    exit 1
fi