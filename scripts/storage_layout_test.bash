#!/bin/bash
output_dir="./test/storage"
for CONTRACTNAME in L1ERC20Gateway L1CustomGateway L1ReverseCustomGateway L1WethGateway L2ERC20Gateway L2CustomGateway L2ReverseCustomGateway L2WethGateway L1GatewayRouter L2GatewayRouter StandardArbERC20
do
    echo "Checking storage change of $CONTRACTNAME"
    [ -f "$output_dir/$CONTRACTNAME" ] && mv "$output_dir/$CONTRACTNAME" "$output_dir/$CONTRACTNAME-old"
    forge inspect "$CONTRACTNAME" --pretty storage > "$output_dir/$CONTRACTNAME"
    diff "$output_dir/$CONTRACTNAME-old" "$output_dir/$CONTRACTNAME"
    if [[ $? != "0" ]]
    then
        CHANGED=1
    fi
done
if [[ $CHANGED == 1 ]]
then
    exit 1
fi