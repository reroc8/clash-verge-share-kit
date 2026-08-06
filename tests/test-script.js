const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const rootDir = path.resolve(__dirname, "..");
const scriptPath = path.join(rootDir, "config", "Script.js");
const mergePath = path.join(rootDir, "config", "Merge.yaml");
const source = fs.readFileSync(scriptPath, "utf8");
const mergeSource = fs.readFileSync(mergePath, "utf8");
vm.runInThisContext(source, { filename: "config/Script.js" });

function run(config) {
  return main(JSON.parse(JSON.stringify(config)), "test-profile");
}

function groupByName(config, name) {
  return (config["proxy-groups"] || []).find((group) => group.name === name);
}

{
  const output = run({
    Proxies: [{ name: "HK-A" }, { name: "US-C" }],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  assert.deepStrictEqual(output.proxies.map((proxy) => proxy.name), ["HK-A", "US-C"]);
  assert.strictEqual(output.Proxies, undefined, "compatibility proxy key must be normalized to lowercase");
  assert.deepStrictEqual(groupByName(output, "HK").proxies, ["HK-A"]);
  assert.deepStrictEqual(groupByName(output, "US").proxies, ["US-C"]);
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "HK-A" }],
    "proxy-groups": [
      { name: "Helper", type: "select", proxies: ["US-A"] },
      { name: "Custom", type: "select", proxies: ["Helper"] }
    ],
    rules: ["DOMAIN-SUFFIX,example.com,Custom", "MATCH,DIRECT"]
  });

  assert(groupByName(output, "Custom"), "custom rule target must survive compact mode");
  assert(groupByName(output, "Helper"), "dependencies of a referenced custom group must survive compact mode");
  assert(output.rules.includes("DOMAIN-SUFFIX,example.com,Custom"));
}

{
  const providerOutput = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "Download Route", type: "select", proxies: ["US-A"] }],
    "rule-providers": {
      custom: { type: "inline", behavior: "domain", proxy: "Download Route", payload: ["example.test"] }
    },
    rules: ["MATCH,DIRECT"]
  });
  assert(groupByName(providerOutput, "Download Route"), "rule-provider proxy target must survive compact mode");

  const subRuleOutput = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-A"] }],
    "sub-rules": {
      custom: ["DOMAIN-SUFFIX,example.test,Custom"]
    },
    rules: ["SUB-RULE,(NETWORK,TCP),custom", "MATCH,DIRECT"]
  });
  assert(groupByName(subRuleOutput, "Custom"), "sub-rule target must survive compact mode");
}

{
  const output = run({
    proxies: [
      { name: "US-Chain", "dialer-proxy": "Custom" },
      { name: "US-Base" }
    ],
    "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-Base"] }],
    rules: ["MATCH,DIRECT"]
  });

  assert(groupByName(output, "Custom"), "dialer-proxy dependencies must survive compact mode");
  assert.strictEqual(output.proxies[0]["dialer-proxy"], "Custom");
}

{
  const output = run({
    proxies: [{ name: "US" }, { name: "TW" }, { name: "Proxies" }, { name: "SG-A" }],
    "proxy-groups": [],
    "rule-providers": {
      test: { type: "inline", behavior: "domain", proxy: "Proxies", payload: ["example.test"] }
    },
    rules: ["MATCH,DIRECT"]
  });

  const usGroup = groupByName(output, "US Group");
  const twGroup = groupByName(output, "TW Group");
  assert(usGroup, "US node collision must allocate US Group");
  assert(twGroup, "TW node collision must allocate TW Group");
  assert.deepStrictEqual(usGroup.proxies, ["US"]);
  assert.deepStrictEqual(twGroup.proxies, ["TW"]);
  assert(!usGroup.proxies.includes(usGroup.name), "US group must not reference itself");
  assert(!twGroup.proxies.includes(twGroup.name), "TW group must not reference itself");
  assert.deepStrictEqual(groupByName(output, "Claude").proxies, ["US Group"]);
  assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US Group", "TW Group"]);
  assert(groupByName(output, "Proxies Group"), "Proxies node collision must allocate Proxies Group");
  assert.strictEqual(output["rule-providers"].test.proxy, "Proxies Group");
}

{
  const output = run({
    proxies: [{ name: "US-bootstrap" }],
    "proxy-providers": {
      airport: { type: "http", url: "https://example.invalid/provider" }
    },
    "proxy-groups": [
      { name: "All Provider Nodes", type: "select", use: ["airport"] },
      { name: "US Provider", type: "url-test", use: ["airport"] }
    ],
    rules: ["MATCH,DIRECT"]
  });

  assert(groupByName(output, "All Provider Nodes"), "mixed subscription must keep provider groups");
  assert(groupByName(output, "US Provider"), "mixed subscription must keep regional provider groups");
  assert(groupByName(output, "Proxies").proxies.includes("All Provider Nodes"));
  assert(groupByName(output, "US").proxies.includes("US Provider"));
}

{
  const output = run({
    "proxy-providers": {
      airport: { type: "inline", payload: [{ name: "US-A" }, { name: "TW-A" }, { name: "SG-A" }] }
    },
    "proxy-groups": [
      { name: "Proxies", type: "select", use: ["airport"] },
      { name: "US", type: "url-test", use: ["airport"], filter: "US" },
      { name: "TW", type: "url-test", use: ["airport"], filter: "TW" },
      { name: "SG", type: "url-test", use: ["airport"], filter: "SG" },
      { name: "Claude", type: "select", use: ["airport"], filter: "US|HK" },
      { name: "AI", type: "select", use: ["airport"], "include-all": true },
      { name: "Exchange", type: "select", use: ["airport"], "exclude-filter": "TW|SG" }
    ],
    rules: ["MATCH,Proxies"]
  });

  assert.deepStrictEqual(groupByName(output, "Proxies").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "US").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "TW").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "SG").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "Claude").proxies, ["US"]);
  assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US", "TW"]);
  assert.deepStrictEqual(groupByName(output, "Exchange").proxies, ["TW", "SG"]);
  assert.strictEqual(groupByName(output, "Claude").use, undefined);
  assert.strictEqual(groupByName(output, "Claude").filter, undefined);
  assert.strictEqual(groupByName(output, "AI").use, undefined);
  assert.strictEqual(groupByName(output, "AI")["include-all"], undefined);
  assert.strictEqual(groupByName(output, "Exchange").use, undefined);
  assert.strictEqual(groupByName(output, "Exchange")["exclude-filter"], undefined);
}

{
  const output = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "proxies", type: "select", proxies: ["US-A"] }],
    rules: ["MATCH,Proxies"]
  });

  assert(groupByName(output, "proxies"), "case-insensitive existing group must be reused");
  assert(output.rules.includes("MATCH,proxies"), "rule target must follow reused group casing");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "TW-A" }, { name: "SG-A" }],
    "proxy-groups": [],
    rules: [
      "DOMAIN,api.okx.com,DIRECT",
      "DOMAIN-SUFFIX,OKX.COM,DIRECT",
      "AND,((DOMAIN-SUFFIX,bybit.com),(NETWORK,TCP)),DIRECT",
      "MATCH,DIRECT"
    ]
  });

  const exactRuleIndex = output.rules.indexOf("DOMAIN,api.okx.com,DIRECT");
  const logicalRuleIndex = output.rules.indexOf("AND,((DOMAIN-SUFFIX,bybit.com),(NETWORK,TCP)),DIRECT");
  const exchangeRuleIndex = output.rules.findIndex((rule) => rule.startsWith("DOMAIN-SUFFIX,okx.com,"));
  assert.strictEqual(exactRuleIndex, 0, "specific subscription rules must keep their original priority");
  assert(logicalRuleIndex < exchangeRuleIndex, "specific logical rules must be allowed to override automatic Exchange routing");
  assert(exactRuleIndex < exchangeRuleIndex, "exact subscription rules must be allowed to override automatic Exchange routing");
  assert(!output.rules.includes("DOMAIN-SUFFIX,OKX.COM,DIRECT"), "case variants of managed exchange rules must be deduplicated");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "TW-A" }, { name: "SG-A" }],
    "proxy-groups": [],
    rules: [
      "DOMAIN-SUFFIX,service.example,Proxies",
      "RULE-SET,cn-domain,DIRECT",
      "RULE-SET,global-domain,Proxies",
      "MATCH,DIRECT"
    ]
  });

  const exchangeIndex = output.rules.findIndex((rule) => rule.startsWith("DOMAIN-SUFFIX,okx.com,"));
  const serviceIndex = output.rules.indexOf("DOMAIN-SUFFIX,service.example,Proxies");
  const cnIndex = output.rules.indexOf("RULE-SET,cn-domain,DIRECT");
  assert(serviceIndex < exchangeIndex, "narrow subscription rules must keep priority over automatic Exchange rules");
  assert(exchangeIndex < cnIndex, "exchange rules must stay before the new domestic/global base layers");
  for (const domain of ["okx-dns1.com", "okx-dns2.com", "bybit-global.com", "binanceapi.com"]) {
    assert(
      output.rules.includes(`DOMAIN-SUFFIX,${domain},Exchange`),
      `${domain} must stay inside the controlled Exchange group`
    );
  }
}

{
  const requiredBusinessRules = [
    "DOMAIN,anthropic.auth0.com,Claude",
    "DOMAIN,anthropic-com.ghost.io,Claude",
    "DOMAIN,anthropic.com.cdn.cloudflare.net,Claude",
    "DOMAIN-SUFFIX,clau.de,Claude",
    "DOMAIN-SUFFIX,claudeusercontent.com,Claude",
    "DOMAIN,openaiassets.blob.core.windows.net,AI",
    "DOMAIN,notebooklm.googleapis.com,AI",
    "DOMAIN-SUFFIX,gemini.gstatic.com,AI",
    "DOMAIN-SUFFIX,generativeai.google,AI"
  ];
  for (const rule of requiredBusinessRules) {
    assert(mergeSource.includes(`- ${rule}`), `${rule} must remain in Merge.yaml`);
  }

  const applicationsIndex = mergeSource.indexOf("- RULE-SET,applications,DIRECT");
  const cnDomainIndex = mergeSource.indexOf("- RULE-SET,cn-domain,DIRECT");
  const globalDomainIndex = mergeSource.indexOf("- RULE-SET,global-domain,Proxies");
  assert(applicationsIndex > 0, "applications rule must exist");
  assert(applicationsIndex < cnDomainIndex, "applications must run before the domestic base layer");
  assert(applicationsIndex < globalDomainIndex, "applications must run before the global base layer");
  for (const domain of ["t.me", "telegra.ph", "telegram-cdn.org", "telegram.org", "telesco.pe"]) {
    assert(
      mergeSource.includes(`- DOMAIN-SUFFIX,${domain},Telegram`),
      `${domain} must use the Telegram group`
    );
  }
  assert(mergeSource.includes("- RULE-SET,telegramcidr,Telegram,no-resolve"), "existing Telegram CIDR routing must remain enabled");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "Proxies" }],
    "proxy-groups": [],
    rules: ["FINAL,Proxies", "FINAL,REJECT"]
  });

  assert(output.rules.includes("MATCH,Proxies Group"), "legacy FINAL rule must become a valid MATCH rule with the allocated group name");
  assert(output.rules.includes("MATCH,REJECT"), "user FINAL reject rule must be preserved");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "Proxies" }],
    "proxy-groups": [],
    rules: [
      "AND,((DOMAIN,example.test),(NETWORK,TCP)),Proxies",
      "OR,((DOMAIN,ads.example.test),(NETWORK,UDP)),REJECT"
    ]
  });

  assert(output.rules.includes("AND,((DOMAIN,example.test),(NETWORK,TCP)),Proxies Group"), "logical rule target must follow the allocated managed group name");
  assert(output.rules.some((rule) => rule.includes("ads.example.test")), "user logical reject rule must be preserved");
}

{
  const output = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "proxies", type: "select", proxies: ["US-A"] }],
    "sub-rules": {
      custom: ["DOMAIN,example.test,Proxies"]
    },
    rules: ["SUB-RULE,(NETWORK,TCP),custom", "MATCH,DIRECT"]
  });

  assert.deepStrictEqual(output["sub-rules"].custom, ["DOMAIN,example.test,proxies"]);
  assert(output.rules.includes("SUB-RULE,(NETWORK,TCP),custom"));
}

{
  const output = run({
    proxies: [{ name: "AI" }, { name: "US-A" }, { name: "TW-A" }],
    "proxy-groups": [],
    "rule-providers": {
      reject: { type: "inline", behavior: "domain", payload: ["ads.test"] }
    },
    "sub-rules": {
      AI: ["DOMAIN,example.test,AI"],
      REJECT: ["DOMAIN,keep.example.test,DIRECT", "RULE-SET,reject,REJECT"]
    },
    rules: [
      "SUB-RULE,(NETWORK,TCP),AI",
      "SUB-RULE,(NETWORK,UDP),REJECT",
      "MATCH,DIRECT"
    ]
  });

  assert(output.rules.includes("SUB-RULE,(NETWORK,TCP),AI"), "sub-rule names must not be rewritten as managed groups");
  assert(output.rules.includes("SUB-RULE,(NETWORK,UDP),REJECT"), "sub-rules named REJECT must not be removed");
  assert.deepStrictEqual(output["sub-rules"].AI, ["DOMAIN,example.test,AI Group"]);
  assert.deepStrictEqual(output["sub-rules"].REJECT, ["DOMAIN,keep.example.test,DIRECT", "RULE-SET,reject,REJECT"], "subscription reject rules inside sub-rules must be preserved");
  assert(output["rule-providers"].reject, "subscription reject rule provider must be preserved");
}

{
  const output = run({
    proxies: [
      { name: "Brazil South America" },
      { name: "Argentina Latin America" },
      { name: "US Los Angeles" }
    ],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  assert.deepStrictEqual(groupByName(output, "US").proxies, ["US Los Angeles"]);
}

{
  const output = run({
    proxies: [{ name: "constructor" }, { name: "toString" }, { name: "__proto__" }],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  assert.deepStrictEqual(
    groupByName(output, "Proxies").proxies.slice(0, 3),
    ["constructor", "toString", "__proto__"],
    "Object.prototype names must remain selectable"
  );
}

{
  // listeners / tunnels / ntp 引用自定义策略组时，必须关闭压缩并保留原始组
  {
    const output = run({
      proxies: [{ name: "US-A" }],
      "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-A"] }],
      listeners: [{ type: "socks", port: 7891, proxy: "Custom" }],
      rules: ["MATCH,DIRECT"]
    });
    assert(groupByName(output, "Custom"), "listeners proxy reference must keep original groups");
  }
  {
    const output = run({
      proxies: [{ name: "US-A" }],
      "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-A"] }],
      tunnels: [{ network: ["tcp", "udp"], proxy: "Custom" }],
      rules: ["MATCH,DIRECT"]
    });
    assert(groupByName(output, "Custom"), "tunnels proxy reference must keep original groups");
  }
  {
    const output = run({
      proxies: [{ name: "US-A" }],
      "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-A"] }],
      ntp: { enable: true, proxy: "Custom" },
      rules: ["MATCH,DIRECT"]
    });
    assert(groupByName(output, "Custom"), "ntp proxy reference must keep original groups");
  }
}

{
  // 规则目标的大小写变体必须改写为实际组名
  const output = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "proxies", type: "select", proxies: ["US-A"] }],
    rules: ["MATCH,PROXIES"]
  });
  assert(output.rules.includes("MATCH,proxies"), "uppercase rule target must be rewritten case-insensitively");
}

{
  // 自定义组名的大小写变体引用同样必须关闭压缩
  const output = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-A"] }],
    rules: ["DOMAIN,example.test,CUSTOM"]
  });
  assert(groupByName(output, "Custom"), "case-variant custom group reference must disable compaction");
}

if (process.env.MIHOMO_BIN) {
  const httpProxy = (name, port, extra = {}) => ({
    name,
    type: "http",
    server: "127.0.0.1",
    port,
    ...extra
  });
  const mihomoCases = [
    {
      name: "dialer-proxy compact dependency",
      config: {
        proxies: [
          httpProxy("US-Chain", 18080, { "dialer-proxy": "Custom" }),
          httpProxy("US-Base", 18081)
        ],
        "proxy-groups": [{ name: "Custom", type: "select", proxies: ["US-Base"] }],
        rules: ["MATCH,DIRECT"]
      }
    },
    {
      name: "sub-rule managed target casing",
      config: {
        proxies: [httpProxy("US-A", 18082)],
        "proxy-groups": [{ name: "proxies", type: "select", proxies: ["US-A"] }],
        "sub-rules": { custom: ["DOMAIN,example.test,Proxies"] },
        rules: ["SUB-RULE,(NETWORK,TCP),custom", "MATCH,DIRECT"]
      }
    },
    {
      name: "sub-rule named REJECT",
      config: {
        proxies: [httpProxy("US-A", 18083)],
        "proxy-groups": [],
        "rule-providers": {
          reject: { type: "inline", behavior: "domain", payload: ["+.ads.test"] }
        },
        "sub-rules": { REJECT: ["DOMAIN,keep.example.test,DIRECT", "RULE-SET,reject,REJECT"] },
        rules: ["SUB-RULE,(NETWORK,TCP),REJECT", "MATCH,DIRECT"]
      }
    }
  ];

  for (const testCase of mihomoCases) {
    const output = run(testCase.config);
    const encoded = Buffer.from(JSON.stringify(output), "utf8").toString("base64");
    const result = childProcess.spawnSync(process.env.MIHOMO_BIN, ["-t", "-config", encoded], {
      encoding: "utf8"
    });
    assert.strictEqual(
      result.status,
      0,
      `${testCase.name} must pass Mihomo validation:\n${result.stdout || ""}${result.stderr || ""}`
    );
  }
  console.log(`Mihomo configuration tests passed: ${mihomoCases.length}`);
}

console.log("Script.js regression tests passed");
