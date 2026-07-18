const assert = require("assert");
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
    rules: ["DOMAIN,example.test,DIRECT"]
  });

  assert(output.rules[0].startsWith("DOMAIN-SUFFIX,okx.com,"), "exchange rules must be inserted before narrow-only rules");
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
  const cnIndex = output.rules.indexOf("RULE-SET,cn-domain,DIRECT");
  assert(exchangeIndex > 0 && exchangeIndex < cnIndex, "exchange rules must stay before the new domestic/global base layers");
  for (const domain of ["okx-dns1.com", "okx-dns2.com", "bybit-global.com", "binanceapi.com"]) {
    assert(
      output.rules.includes(`DOMAIN-SUFFIX,${domain},Exchange`),
      `${domain} must stay inside the controlled Exchange group`
    );
  }
}

{
  const requiredBusinessRules = [
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
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "Proxies" }],
    "proxy-groups": [],
    rules: ["FINAL,Proxies", "FINAL,REJECT"]
  });

  assert(output.rules.includes("MATCH,Proxies Group"), "legacy FINAL rule must become a valid MATCH rule with the allocated group name");
  assert(!output.rules.includes("MATCH,REJECT"), "legacy FINAL reject rule must be removed with other reject rules");
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
  assert(!output.rules.some((rule) => rule.includes("ads.example.test")), "logical reject rule must be removed with other reject rules");
}

console.log("Script.js regression tests passed");
