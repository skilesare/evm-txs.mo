module {
    public type TransactionType = {
        #Legacy;
        #EIP1559;
        #EIP2930;
    };

    public type TransactionLegacy = {
        chainId: Nat64;
        nonce: Nat64;
        gasPrice: Nat64;
        gasLimit: Nat64;
        to: Text;
        value: Nat64;
        data: Text;
        v: Text;
        r: Text;
        s: Text;
    };

    public type Transaction2930 = {
        chainId: Nat64;
        nonce: Nat64;
        gasPrice: Nat64;
        gasLimit: Nat64;
        to: Text;
        value: Nat64;
        data: Text;
        accessList: [(Text, [Text])];
        v: Text;
        r: Text;
        s: Text;
    };

    public type Transaction1559 = {
        chainId: Nat64;
        nonce: Nat64;
        maxPriorityFeePerGas: Nat64;
        maxFeePerGas: Nat64;
        gasLimit: Nat64;
        to: Text;
        value: Nat64;
        data: Text;
        accessList: [(Text, [Text])];
        v: Text;
        r: Text;
        s: Text;
    };
}