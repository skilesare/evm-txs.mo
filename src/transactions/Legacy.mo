import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Int64 "mo:base/Int64";
import Rlp "mo:rlp";
import RlpTypes "mo:rlp/types";
import Recover "mo:libsecp256k1/Recover";
import Types "../Types";
import Utils "../utils/Utils";
import ArrayUtils "../utils/ArrayUtils";
import TextUtils "../utils/TextUtils";
import Helper "Helper";

module Legacy {
    public func from(
        data: ([Nat8], Nat64)
    ): ?Types.TransactionLegacy {
        switch(Rlp.decode(#Uint8Array(Buffer.fromArray(data.0)))) {
            case (#err(_)) {
                return null;
            };
            case (#ok(dec)) {
                switch(dec) {
                    case (#Nested(list)) {
                        let nonce = Utils.rlpGetAsNat64(list.get(0));
                        let gasPrice = Utils.rlpGetAsNat64(list.get(1));
                        let gasLimit = Utils.rlpGetAsNat64(list.get(2));
                        let to = Utils.rlpGetAsText(list.get(3));
                        let value = Utils.rlpGetAsNat64(list.get(4));
                        let dataTx = Utils.rlpGetAsText(list.get(5));
                        let v = Utils.rlpGetAsText(list.get(6));
                        let r = Utils.rlpGetAsText(list.get(7));
                        let s = Utils.rlpGetAsText(list.get(8));

                        let chainId = data.1;

                        return ?{
                            chainId = chainId;
                            nonce = nonce;
                            gasPrice = gasPrice;
                            gasLimit = gasLimit;
                            to = to;
                            value = value;
                            data = dataTx;
                            v = v;
                            r = r;
                            s = s;
                        };
                    };
                    case _ {
                        return null;
                    };
                };
            };
        };
    };

    public func getMessageToSign(
        tx: Types.TransactionLegacy
    ): Result.Result<[Nat8], Text> {
        
        let items: [[Nat8]] = [
            Utils.nat64ToNat8Array(tx.nonce),
            Utils.nat64ToNat8Array(tx.gasPrice),
            Utils.nat64ToNat8Array(tx.gasLimit),
            Utils.hexTextToNat8Array(tx.to),
            Utils.nat64ToNat8Array(tx.value),
            Utils.hexTextToNat8Array(tx.data),
            Utils.nat64ToNat8Array(tx.chainId),
        ];

        let buf = Buffer.Buffer<RlpTypes.Input>(items.size() + 2);
        for(item in items.vals()) {
            buf.add(#Uint8Array(Buffer.fromArray(item)));
        };

        buf.add(#Null);
        buf.add(#Null);

        switch(Rlp.encode(#List(buf))) {
            case (#err(msg)) {
                return #err(msg);
            };
            case (#ok(enc)) {
                let hash = Utils.calcKeccak(Buffer.toArray(enc), 256);
                return #ok(hash);
            };
        };
    };

    public func sign(
        tx: Types.TransactionLegacy,
        signature: [Nat8],
        publicKey: [Nat8],
        ctx: Recover.Context,
    ): Result.Result<Types.TransactionLegacy, Text> {
        let chain_id = tx.chainId;

        let r_remove_leading_zeros = ArrayUtils.stripLeft(ArrayUtils.left(signature, 31), func(e: Nat8): Bool = e == 0);
        let s_remove_leading_zeros = ArrayUtils.stripLeft(ArrayUtils.right<Nat8>(signature, 32), func(e: Nat8): Bool = e == 0);

        let r = Utils.nat8ArrayToHexText(r_remove_leading_zeros);
        let s = Utils.nat8ArrayToHexText(s_remove_leading_zeros);

        switch(getMessageToSign(tx)) {
            case (#err(msg)) {
                return #err(msg);
            };
            case (#ok(message)) {
                switch(Helper.getRecoveryId(message, signature, publicKey, ctx)) {
                    case (#err(msg)) {
                        return #err(msg);
                    };
                    case (#ok(recovery_id)) {
                        let v_number = chain_id * 2 + 35 + Nat64.fromNat(Nat8.toNat(recovery_id));
                        let v = Utils.nat8ArrayToHexText(Utils.nat64ToNat8Array(v_number));

                        return #ok({
                            tx
                            with
                            v = v;
                            r = r;
                            s = s;
                        });
                    };
                };
            };
        };
    };

    public func signAndSerialize(
        tx: Types.TransactionLegacy,
        signature: [Nat8],
        publicKey: [Nat8],
        ctx: Recover.Context,
    ): Result.Result<[Nat8], Text> {
        switch(sign(tx, signature, publicKey, ctx)) {
            case (#err(msg)) {
                return #err(msg);
            };
            case (#ok(signedTx)) {
                return serialize(signedTx);
            };
        };
    };

    public func isSigned(
        tx: Types.TransactionLegacy
    ): Bool {
        let r = if(Text.startsWith(tx.r, #text("0x"))) {
            TextUtils.right(tx.r, 2);
        } else {
            tx.r;
        };

        let s = if(Text.startsWith(tx.s, #text("0x"))) {
            TextUtils.right(tx.s, 2);
        } else {
            tx.s;
        };

        return r != "00" or s != "00";
    };

    public func getSignature(
        tx: Types.TransactionLegacy
    ): Result.Result<[Nat8], Text> {
        if(not isSigned(tx)) {
            return #err("This is not a signed transaction");
        };

        let r = Buffer.fromArray<Nat8>(Utils.hexTextToNat8Array(tx.r));
        let s = Buffer.fromArray<Nat8>(Utils.hexTextToNat8Array(tx.s));
        let res = Buffer.Buffer<Nat8>(r.size() + s.size());
        res.append(r);
        res.append(s);

        return #ok(Buffer.toArray(res));
    };

    public func getRecoveryId(
        tx: Types.TransactionLegacy
    ): Result.Result<Nat8, Text> {
        if(not isSigned(tx)) {
            return #err("This is not a signed transaction");
        };
        
        let chain_id = tx.chainId;
        let v = Utils.hexTextToNat8Array(tx.v);

        let recovery_id = -1 * Int64.fromNat64(((chain_id * 2) + 35 - Nat64.fromNat(Nat8.toNat(v[0]))));
        return #ok(Nat8.fromNat(Nat64.toNat(Int64.toNat64(recovery_id))));
    };

    public func serialize(
        tx: Types.TransactionLegacy
    ): Result.Result<[Nat8], Text> {

        let items: [[Nat8]] = [
            Utils.nat64ToNat8Array(tx.nonce),
            Utils.nat64ToNat8Array(tx.gasPrice),
            Utils.nat64ToNat8Array(tx.gasLimit),
            Utils.hexTextToNat8Array(tx.to),
            Utils.nat64ToNat8Array(tx.value),
            Utils.hexTextToNat8Array(tx.data),
            Utils.hexTextToNat8Array(tx.v),
            Utils.hexTextToNat8Array(tx.r),
            Utils.hexTextToNat8Array(tx.s)
        ];

        let buf = Buffer.Buffer<RlpTypes.Input>(items.size());
        for(item in items.vals()) {
            buf.add(#Uint8Array(Buffer.fromArray(item)));
        };

        switch(Rlp.encode(#List(buf))) {
            case (#err(msg)) {
                return #err(msg);
            };
            case (#ok(enc)) {
                return #ok(Buffer.toArray<Nat8>(enc));
            };
        };
    };
};