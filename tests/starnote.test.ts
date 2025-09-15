import { Clarinet, Tx, Chain, Account, types } from "clarinet";

Clarinet.test({
  name: "StarNote: post notes, like, leading-post updates, and prevents double-likes",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const alice = accounts.get("wallet_1")!;
    const bob = accounts.get("wallet_2")!;
    const v1 = accounts.get("wallet_3")!;
    const v2 = accounts.get("wallet_4")!;

    // Alice posts (id = 1)
    let block = chain.mineBlock([
      Tx.contractCall("starnote", "post", [types.ascii("Dawn breaks, code sings")], alice.address),
    ]);
    block.receipts[0].result.expectOk().expectUint(1);

    // Bob posts (id = 2)
    block = chain.mineBlock([
      Tx.contractCall("starnote", "post", [types.ascii("Night fades, hope grows")], bob.address),
    ]);
    block.receipts[0].result.expectOk().expectUint(2);

    // v1 likes Alice's post (1)
    block = chain.mineBlock([
      Tx.contractCall("starnote", "like", [types.uint(1)], v1.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // v2 likes Alice's post (1) => Alice now has 2 likes
    block = chain.mineBlock([
      Tx.contractCall("starnote", "like", [types.uint(1)], v2.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // Check Alice's post likes via read-only
    const p1 = chain.callReadOnlyFn("starnote", "get-post", [types.uint(1)], deployer.address);
    const tup = p1.result.expectSome().expectTuple();
    tup["author"].expectPrincipal(alice.address);
    tup["likes"].expectUint(2);

    // Leading post id should be 1 with 2 likes
    const leadingId = chain.callReadOnlyFn("starnote", "get-leading-id", [], deployer.address);
    leadingId.result.expectUint(1);
    const leadingLikes = chain.callReadOnlyFn("starnote", "get-leading-likes", [], deployer.address);
    leadingLikes.result.expectUint(2);

    // v1 tries to like post 1 again -> should error (ERR-ALREADY-LIKED = 101)
    block = chain.mineBlock([
      Tx.contractCall("starnote", "like", [types.uint(1)], v1.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(101);
  },
});
