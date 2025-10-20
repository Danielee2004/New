import { Clarinet, Tx, Chain, Account, types } from "clarinet";

Clarinet.test({
  name: "Chinese-coin: initialize, mint, transfer, approve/transfer-from, pause and blacklist work; cap enforced",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const alice = accounts.get("wallet_1")!;
    const bob = accounts.get("wallet_2")!;

    // Initialize owner as deployer
    let block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "initialize", [types.principal(deployer.address)], deployer.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // Metadata
    const name = chain.callReadOnlyFn("chinese-coin", "get-name", [], deployer.address);
    name.result.expectOk().expectAscii("Chinese-coin");
    const symbol = chain.callReadOnlyFn("chinese-coin", "get-symbol", [], deployer.address);
    symbol.result.expectOk().expectAscii("CHNC");
    const decimals = chain.callReadOnlyFn("chinese-coin", "get-decimals", [], deployer.address);
    decimals.result.expectOk().expectUint(8);

    // Mint 1,000_00000000 (1,000 with 8 decimals) to Alice
    const amount = 1000n * 10n ** 8n;
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "mint", [types.principal(alice.address), types.uint(amount)], deployer.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    let balA = chain.callReadOnlyFn("chinese-coin", "get-balance", [types.principal(alice.address)], deployer.address);
    balA.result.expectOk().expectUint(amount);

    // Transfer 100 to Bob
    const hundred = 100n * 10n ** 8n;
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "transfer", [types.uint(hundred), types.principal(alice.address), types.principal(bob.address), types.none()], alice.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    let balB = chain.callReadOnlyFn("chinese-coin", "get-balance", [types.principal(bob.address)], deployer.address);
    balB.result.expectOk().expectUint(hundred);

    // Approve Bob to spend 50 from Alice, then transfer-from 40
    const fifty = 50n * 10n ** 8n;
    const forty = 40n * 10n ** 8n;
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "approve", [types.principal(bob.address), types.uint(fifty)], alice.address),
      Tx.contractCall("chinese-coin", "transfer-from", [types.principal(alice.address), types.principal(bob.address), types.uint(forty), types.none()], bob.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    block.receipts[1].result.expectOk().expectBool(true);

    // Pause transfers
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "set-paused", [types.bool(true)], deployer.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // Attempt transfer while paused -> err 101
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "transfer", [types.uint(1), types.principal(alice.address), types.principal(bob.address), types.none()], alice.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(101);

    // Unpause and blacklist Bob, then transfer -> err 102
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "set-paused", [types.bool(false)], deployer.address),
      Tx.contractCall("chinese-coin", "set-blacklist", [types.principal(bob.address), types.bool(true)], deployer.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    block.receipts[1].result.expectOk().expectBool(true);

    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "transfer", [types.uint(1), types.principal(alice.address), types.principal(bob.address), types.none()], alice.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(102);

    // Cap enforcement: try to mint above cap
    const cap = 21000000n * 10n ** 8n;
    // Set total supply close to cap via a large mint to deployer (allowed)
    const currentSupply = chain.callReadOnlyFn("chinese-coin", "get-total-supply", [], deployer.address);
    const mintedSoFar = BigInt(currentSupply.result.expectOk().toString());
    const toMint = cap - mintedSoFar;
    if (toMint > 0n) {
      block = chain.mineBlock([
        Tx.contractCall("chinese-coin", "mint", [types.principal(deployer.address), types.uint(toMint)], deployer.address),
      ]);
      block.receipts[0].result.expectOk().expectBool(true);
    }
    // Now mint 1 more should fail with 105
    block = chain.mineBlock([
      Tx.contractCall("chinese-coin", "mint", [types.principal(deployer.address), types.uint(1)], deployer.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(105);
  },
});
