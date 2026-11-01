const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const http = require("http");
const net = require("net");
const os = require("os");
const path = require("path");
const vm = require("vm");

const rootDir = path.resolve(__dirname, "..");
const scriptPath = path.join(rootDir, "config", "Script.js");
const mergePath = path.join(rootDir, "config", "Merge.yaml");
const source = fs.readFileSync(scriptPath, "utf8");
const mergeSource = fs.readFileSync(mergePath, "utf8");
const unifiedGoogleGroup = "Google + YouTube + Telegram";
vm.runInThisContext(source, { filename: "config/Script.js" });

function run(config) {
  return main(JSON.parse(JSON.stringify(config)), "test-profile");
}

// Merge.yaml 的解析 + 下载源替身：E2E 必须让「Merge.yaml 的规则」与订阅真正一起跑一遍。
// 此前对 Merge.yaml 的断言都只看字符串（规则存在、provider 有定义），规则本身从未
// 在「无对应地区节点的订阅」上通过内核校验 —— 而 dola.com→SG 正是在这种订阅上
// 让 mihomo 拒绝整份配置（proxy [SG] not found）。
function mergeRulesFromYaml(source) {
  const rules = [];
  const lines = source.split(/\r?\n/);
  let inRules = false;
  for (const line of lines) {
    if (/^rules:\s*$/.test(line)) {
      inRules = true;
      continue;
    }
    if (inRules) {
      if (/^[A-Za-z0-9_-]+:/.test(line)) {
        break;
      }
      const match = line.match(/^\s{2}- (.+)$/);
      if (match) {
        rules.push(match[1].trim());
      }
    }
  }
  return rules;
}

function mergeProviderStubs(rules) {
  const names = new Set();
  for (const rule of rules) {
    const match = /^RULE-SET,([^,]+),/.exec(rule);
    if (match) {
      names.add(match[1]);
    }
  }
  const providers = {};
  for (const name of names) {
    providers[name] = { type: "inline", behavior: "domain", payload: [] };
  }
  return providers;
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
  assert(!groupByName(output, "Claude"), "new subscriptions must not get a second visible Claude group");
  assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US Group"]);
  assert(groupByName(output, "Proxies Group"), "Proxies node collision must allocate Proxies Group");
  assert.strictEqual(output["rule-providers"].test.proxy, "Proxies Group");
}

// UK 地区识别（本轮新增地区组）：emoji、英文全名、缩写都应命中，且不与其他地区串味
{
  const output = run({
    proxies: [{ name: "🇬🇧 London-01" }, { name: "United Kingdom-A" }, { name: "UK-B" }, { name: "HK-A" }],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  const ukGroup = groupByName(output, "UK");
  assert(ukGroup, "UK region group must be generated when UK nodes are present");
  assert.deepStrictEqual(
    ukGroup.proxies.slice().sort(),
    ["UK-B", "United Kingdom-A", "🇬🇧 London-01"].sort()
  );
  assert(!ukGroup.proxies.includes("HK-A"), "HK node must not leak into the UK group");
  assert(groupByName(output, "HK"), "HK group must still be generated alongside UK");
}

{
  // rule-provider.proxy 的大小写变体必须与规则目标同一套 lookupName 语义改写：
  // 订阅组名为小写 proxies（被沿用），provider 写 PROXIES 不能悬空
  const output = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "proxies", type: "select", proxies: ["US-A"] }],
    "rule-providers": {
      test: { type: "inline", behavior: "domain", proxy: "PROXIES", payload: ["example.test"] }
    },
    rules: ["MATCH,DIRECT"]
  });

  assert(groupByName(output, "proxies"), "subscription lowercase proxies group must be inherited");
  assert.strictEqual(
    output["rule-providers"].test.proxy,
    "proxies",
    "rule-provider proxy must be rewritten case-insensitively to the inherited group name"
  );
}

{
  // compact 引用检测对 provider.proxy 的大小写变体同样敏感，不误删被引用的自定义组
  const output = run({
    proxies: [{ name: "US-A" }, { name: "HK-A" }],
    "proxy-groups": [{ name: "MyRoute", type: "select", proxies: ["HK-A"] }],
    "rule-providers": {
      custom: { type: "inline", behavior: "domain", proxy: "MYROUTE", payload: ["example.test"] }
    },
    rules: ["MATCH,DIRECT"]
  });

  assert(
    groupByName(output, "MyRoute"),
    "case-variant rule-provider proxy must keep the referenced custom group alive in compact mode"
  );
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
  assert.deepStrictEqual(groupByName(output, "US").proxies, ["US-bootstrap"], "US must not trust a regional provider group by name");
  assert.deepStrictEqual(groupByName(output, "US").use, ["airport"], "provider access must survive behind the restricted filter");
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
      { name: "Google", type: "select", use: ["airport"], filter: "TW|US" },
      { name: "YouTube", type: "select", use: ["airport"], filter: "TW|US" },
      { name: "Telegram", type: "select", use: ["airport"], filter: "TW|US" },
      { name: "AI", type: "select", use: ["airport"], "include-all": true },
      { name: "Exchange", type: "select", use: ["airport"], "exclude-filter": "TW|SG" }
    ],
    rules: [
      "DOMAIN-SUFFIX,claude.example,Claude",
      "DOMAIN-SUFFIX,google.example,Google",
      "DOMAIN-SUFFIX,youtube.example,YouTube",
      "DOMAIN-SUFFIX,telegram.example,Telegram",
      "MATCH,Proxies"
    ]
  });

  assert.deepStrictEqual(groupByName(output, "Proxies").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "US").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "TW").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "SG").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US"]);
  assert.strictEqual(groupByName(output, "Claude").hidden, true);
  assert.deepStrictEqual(groupByName(output, "Claude").proxies, ["AI"]);
  assert(output.rules.includes("DOMAIN-SUFFIX,claude.example,AI"), "legacy Claude rule targets must map to AI");
  for (const alias of ["Google", "YouTube", "Telegram"]) {
    assert.strictEqual(groupByName(output, alias).hidden, true, `${alias} legacy group must be hidden`);
    assert.deepStrictEqual(groupByName(output, alias).proxies, [unifiedGoogleGroup]);
    assert.strictEqual(groupByName(output, alias).use, undefined);
    assert.strictEqual(groupByName(output, alias).filter, undefined);
  }
  assert(output.rules.includes(`DOMAIN-SUFFIX,google.example,${unifiedGoogleGroup}`), "legacy Google rule target must map to the unified group");
  assert(output.rules.includes(`DOMAIN-SUFFIX,youtube.example,${unifiedGoogleGroup}`), "legacy YouTube rule target must map to the unified group");
  assert(output.rules.includes(`DOMAIN-SUFFIX,telegram.example,${unifiedGoogleGroup}`), "legacy Telegram rule target must map to the unified group");
  assert.deepStrictEqual(groupByName(output, unifiedGoogleGroup).proxies.slice(0, 3), ["TW", "SG", "US"]);
  assert.deepStrictEqual(groupByName(output, "Exchange").proxies, ["TW", "SG"]);
  assert.strictEqual(groupByName(output, "Claude").use, undefined);
  assert.strictEqual(groupByName(output, "Claude").filter, undefined);
  assert.strictEqual(groupByName(output, "AI").use, undefined);
  assert.strictEqual(groupByName(output, "AI")["include-all"], undefined);
  assert.strictEqual(groupByName(output, "Exchange").use, undefined);
  assert.strictEqual(groupByName(output, "Exchange")["exclude-filter"], undefined);
}

// 机场技术组保留给原始规则使用，但不应和三层核心组一起占据代理页入口。
// 普通自定义组仍然可见，避免把用户自己的策略入口误判为技术组。
{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "TW-A" }],
    "proxy-groups": [
      { name: "PROXY", type: "select", proxies: ["US-A", "TW-A"] },
      { name: "GLOBAL", type: "select", proxies: ["PROXY", "DIRECT"] },
      { name: "订阅更新", type: "fallback", proxies: ["PROXY", "DIRECT"] },
      { name: "我的备用", type: "select", proxies: ["US-A"] }
    ],
    rules: ["MATCH,PROXY"]
  });

  for (const name of ["PROXY", "GLOBAL", "订阅更新"]) {
    assert.strictEqual(groupByName(output, name).hidden, true, `${name} technical group must be hidden`);
  }
  assert.strictEqual(groupByName(output, "Proxies").hidden, undefined, "managed Proxies group must remain visible");
  assert.strictEqual(groupByName(output, "我的备用").hidden, undefined, "ordinary custom groups must remain visible");
  assert(output.rules.includes("MATCH,PROXY"), "hidden technical group must remain a valid rule target");
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
      "DOMAIN-SUFFIX,bybit.com,Exchange",
      "AND,((DOMAIN-SUFFIX,bybit.com),(NETWORK,TCP)),DIRECT",
      "MATCH,DIRECT"
    ]
  });

  const exactRuleIndex = output.rules.indexOf("DOMAIN,api.okx.com,DIRECT");
  const userDirectIndex = output.rules.indexOf("DOMAIN-SUFFIX,OKX.COM,DIRECT");
  const logicalRuleIndex = output.rules.indexOf("AND,((DOMAIN-SUFFIX,bybit.com),(NETWORK,TCP)),DIRECT");
  const exchangeRuleIndex = output.rules.findIndex((rule) => rule.startsWith("DOMAIN-SUFFIX,okx.com,"));
  assert.strictEqual(exactRuleIndex, 0, "specific subscription rules must keep their original priority");
  assert(userDirectIndex !== -1 && userDirectIndex < exchangeRuleIndex, "user rules with non-Exchange targets must survive dedup and keep priority");
  assert(logicalRuleIndex < exchangeRuleIndex, "specific logical rules must be allowed to override automatic Exchange routing");
  assert(exactRuleIndex < exchangeRuleIndex, "exact subscription rules must be allowed to override automatic Exchange routing");
  const bybitExchangeCount = output.rules.filter((rule) => rule === "DOMAIN-SUFFIX,bybit.com,Exchange").length;
  assert.strictEqual(bybitExchangeCount, 1, "rules already targeting the managed Exchange group must be deduplicated");
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
  for (const domain of ["okx-dns1.com", "okx-dns2.com", "bybit-global.com", "binanceapi.com", "bybit.ada.support"]) {
    assert(
      output.rules.includes(`DOMAIN-SUFFIX,${domain},Exchange`),
      `${domain} must stay inside the controlled Exchange group`
    );
  }
}

{
  // 无兜底规则（无 MATCH/FINAL）时，用户具体规则仍须优先于自动注入的交易所规则
  const output = run({
    proxies: [{ name: "US-A" }, { name: "TW-A" }, { name: "SG-A" }],
    "proxy-groups": [],
    rules: ["DOMAIN-SUFFIX,service.example,Proxies"]
  });

  const serviceIndex = output.rules.indexOf("DOMAIN-SUFFIX,service.example,Proxies");
  const exchangeIndex = output.rules.findIndex((rule) => rule.startsWith("DOMAIN-SUFFIX,okx.com,"));
  assert(serviceIndex !== -1 && exchangeIndex !== -1, "user rule and managed exchange rule must both exist");
  assert(serviceIndex < exchangeIndex, "without a catch-all rule, exchange rules must be appended after user rules");
}

{
  const requiredBusinessRules = [
    "DOMAIN,anthropic.auth0.com,AI",
    "DOMAIN,anthropic-com.ghost.io,AI",
    "DOMAIN,anthropic.com.cdn.cloudflare.net,AI",
    "DOMAIN-SUFFIX,clau.de,AI",
    "DOMAIN-SUFFIX,claudeusercontent.com,AI",
    "DOMAIN,openaiassets.blob.core.windows.net,AI",
    `DOMAIN,notebooklm.googleapis.com,${unifiedGoogleGroup}`,
    `DOMAIN-SUFFIX,gemini.gstatic.com,${unifiedGoogleGroup}`,
    `DOMAIN-SUFFIX,generativeai.google,${unifiedGoogleGroup}`,
    "DOMAIN-SUFFIX,tgalileo.com,Proxies",
    "DOMAIN-SUFFIX,lexmount.com,US",
    "DOMAIN-SUFFIX,wjkc.xyz,TW",
    "PROCESS-NAME-REGEX,(?i)^muse,AI",
    "DOMAIN-SUFFIX,muse.meta.com,AI",
    "DOMAIN-SUFFIX,muse.ai,AI",
    "DOMAIN-SUFFIX,dola.com,SG",
    `DOMAIN-SUFFIX,priceai.cc,${unifiedGoogleGroup}`,
    `DOMAIN-SUFFIX,982xj.xyz,${unifiedGoogleGroup}`,
    "DOMAIN-SUFFIX,featuregates.org,AI",
    "DOMAIN-SUFFIX,featureassets.org,AI",
    "DOMAIN-SUFFIX,statsigapi.net,AI",
    "DOMAIN-SUFFIX,statsig.com,AI"
  ];
  for (const rule of requiredBusinessRules) {
    assert(mergeSource.includes(`- ${rule}`), `${rule} must remain in Merge.yaml`);
  }
  for (const rulePrefix of [
    "- DOMAIN-SUFFIX,gemini.google.com",
    "- DOMAIN-SUFFIX,notebooklm.google.com",
    "- DOMAIN,notebooklm.googleapis.com",
    "- DOMAIN-SUFFIX,gemini.gstatic.com"
  ]) {
    const rule = `${rulePrefix},${unifiedGoogleGroup}`;
    assert(mergeSource.includes(rule), `${rule} must remain on the unified Google/YouTube/Telegram group`);
    assert(!mergeSource.includes(`${rulePrefix},AI`), `${rule} must not regress to the US-only AI group`);
  }

  const applicationsIndex = mergeSource.indexOf("- RULE-SET,applications,DIRECT");
  const cnDomainIndex = mergeSource.indexOf("- RULE-SET,cn-domain,DIRECT");
  const globalDomainIndex = mergeSource.indexOf("- RULE-SET,global-domain,Proxies");
  assert(applicationsIndex > 0, "applications rule must exist");
  assert(applicationsIndex < cnDomainIndex, "applications must run before the domestic base layer");
  assert(applicationsIndex < globalDomainIndex, "applications must run before the global base layer");

  // AI 专属功能开关与 Statsig 域名必须在通用规则集之前，否则会被国内直连或普通海外规则抢先命中。
  const aiCompanionRules = [
    "- DOMAIN-SUFFIX,featuregates.org,AI",
    "- DOMAIN-SUFFIX,featureassets.org,AI",
    "- DOMAIN-SUFFIX,statsigapi.net,AI",
    "- DOMAIN-SUFFIX,statsig.com,AI"
  ];
  for (const companionRule of aiCompanionRules) {
    const companionIndex = mergeSource.indexOf(companionRule);
    assert(companionIndex > 0, `${companionRule} must exist in Merge.yaml`);
    assert(companionIndex < applicationsIndex, `${companionRule} must precede applications`);
    assert(companionIndex < cnDomainIndex, `${companionRule} must precede cn-domain`);
    assert(companionIndex < globalDomainIndex, `${companionRule} must precede global-domain`);
  }
  for (const sharedRule of [
    "- DOMAIN-SUFFIX,hcaptcha.com,AI",
    "- DOMAIN-SUFFIX,challenges.cloudflare.com,AI",
    "- DOMAIN-SUFFIX,stripe.com,AI",
    "- DOMAIN-SUFFIX,stripe.network,AI"
  ]) {
    assert(!mergeSource.includes(sharedRule), `${sharedRule} must not force shared traffic into the US-only AI group`);
  }

  // 只限制 OpenAI/ChatGPT 的 UDP/443；不能把对方配置的全局 QUIC/STUN 拒绝策略带进基础包。
  const aiQuicRules = [
    "- AND,((NETWORK,udp),(DST-PORT,443),(DOMAIN-SUFFIX,oaiusercontent.com)),REJECT",
    "- AND,((NETWORK,udp),(DST-PORT,443),(DOMAIN-SUFFIX,oaistatic.com)),REJECT",
    "- AND,((NETWORK,udp),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT",
    "- AND,((NETWORK,udp),(DST-PORT,443),(DOMAIN-SUFFIX,chatgpt.com)),REJECT"
  ];
  const aiDomainIndex = mergeSource.indexOf("- DOMAIN-SUFFIX,chatgpt.com,AI");
  assert(aiDomainIndex > 0, "ChatGPT AI route must exist");
  for (const quicRule of aiQuicRules) {
    const quicIndex = mergeSource.indexOf(quicRule);
    assert(quicIndex > 0, `${quicRule} must exist in Merge.yaml`);
    assert(quicIndex < aiDomainIndex, `${quicRule} must precede the AI domain routes`);
  }
  assert(!mergeSource.includes("- AND,((NETWORK,udp),(DST-PORT,443)),REJECT"), "global UDP/443 reject must stay out of the conservative AI layer");
  assert(!mergeSource.includes("- DOMAIN-KEYWORD,stun,REJECT"), "global STUN reject must stay out of the conservative AI layer");

  // tgalileo.com 唯一会被 cn-domain（+.tgalileo.com）劫持成 DIRECT，位次是这条规则生效的唯一前提，
  // 所以只断言"规则存在"不够：必须同时盯住位次。applications / global-domain 实测不含该域，
  // 但保持业务规则在通用直连层之前的约定，属廉价保险。
  const tgalileoIndex = mergeSource.indexOf("- DOMAIN-SUFFIX,tgalileo.com,Proxies");
  assert(tgalileoIndex > 0, "tgalileo rule must exist");
  assert(
    tgalileoIndex < cnDomainIndex,
    "tgalileo rule must precede the domestic base layer, otherwise cn-domain sends it to DIRECT"
  );
  assert(
    tgalileoIndex < applicationsIndex,
    "tgalileo rule must precede the generic application bypass layer"
  );

  // 出口定向规则（lexmount / wjkc / Meta Muse / muse.ai / Dola / PriceAI / 982xj）。
  // 位次是它们生效的前提：Muse 桌面版实际连的是 graph.facebook.com（在 global-domain 内），
  // muse.ai 在 tld-proxy 内；lexmount.com、dola.com、priceai.cc 与 982xj.xyz 不在任何规则集
  // （会落到兜底 DIRECT，实测国内直连 Cloudflare 落 LAX、秒级超时）。
  // 统一断言它们排在全部通用规则集之前。
  const tldProxyIndex = mergeSource.indexOf("- RULE-SET,tld-proxy,Proxies");
  assert(tldProxyIndex > 0, "tld-proxy rule must exist");
  const directedExitRules = [
    "- DOMAIN-SUFFIX,lexmount.com,US",
    "- DOMAIN-SUFFIX,wjkc.xyz,TW",
    "- PROCESS-NAME-REGEX,(?i)^muse,AI",
    "- DOMAIN-SUFFIX,muse.meta.com,AI",
    "- DOMAIN-SUFFIX,muse.ai,AI",
    "- DOMAIN-SUFFIX,dola.com,SG",
    `- DOMAIN-SUFFIX,priceai.cc,${unifiedGoogleGroup}`,
    `- DOMAIN-SUFFIX,982xj.xyz,${unifiedGoogleGroup}`
  ];
  for (const directedRule of directedExitRules) {
    const directedIndex = mergeSource.indexOf(directedRule);
    assert(directedIndex > 0, `${directedRule} must exist in Merge.yaml`);
    assert(
      directedIndex < globalDomainIndex,
      `${directedRule} must precede global-domain, otherwise it loses to the generic proxy layer`
    );
    assert(
      directedIndex < tldProxyIndex,
      `${directedRule} must precede tld-proxy, otherwise it loses to the generic proxy layer`
    );
    assert(
      directedIndex < cnDomainIndex,
      `${directedRule} must precede cn-domain, otherwise the domestic layer may claim it`
    );
  }
  for (const domain of ["t.me", "telegra.ph", "telegram-cdn.org", "telegram.org", "telesco.pe"]) {
    assert(
      mergeSource.includes(`- DOMAIN-SUFFIX,${domain},${unifiedGoogleGroup}`),
      `${domain} must use the unified Google/YouTube/Telegram group`
    );
  }
  assert(mergeSource.includes(`- RULE-SET,telegramcidr,${unifiedGoogleGroup},no-resolve`), "existing Telegram CIDR routing must remain enabled");
}

{
  // Merge.yaml 中每条 RULE-SET 引用的 provider 必须都有定义，避免规则指向不存在的下载源
  const providerNames = new Set(
    (mergeSource.match(/^  ([a-zA-Z0-9_-]+):\s*$/gm) || [])
      .map((line) => line.trim().replace(/:$/, ""))
  );
  assert(providerNames.size >= 10, "expected rule-providers to be defined in Merge.yaml");
  const referenced = new Set(
    (mergeSource.match(/RULE-SET,([a-zA-Z0-9_-]+),/g) || [])
      .map((token) => token.replace(/^RULE-SET,/, "").replace(/,.*$/, ""))
  );
  for (const name of referenced) {
    assert(providerNames.has(name), `RULE-SET references undefined provider: ${name}`);
  }
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
  // 节点名恰好叫 Proxies 时，受管组改用备用名，sub-rule 目标必须同步改写为同一备用名
  const output = run({
    proxies: [{ name: "Proxies" }, { name: "US-A" }, { name: "TW-A" }],
    "proxy-groups": [],
    "sub-rules": {
      custom: ["DOMAIN-SUFFIX,gpt.example,Proxies"]
    },
    rules: ["SUB-RULE,(NETWORK,TCP),custom", "MATCH,DIRECT"]
  });

  const fallbackGroup = output["proxy-groups"].find(
    (group) => /^Proxies /.test(group.name)
  );
  assert(fallbackGroup, "node named Proxies must force the managed group to a fallback name");
  assert.deepStrictEqual(
    output["sub-rules"].custom,
    [`DOMAIN-SUFFIX,gpt.example,${fallbackGroup.name}`],
    "sub-rule targets must follow the fallback managed group name when a node steals the canonical name"
  );
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
      proxies: [{ name: "US-A" }, { name: "TW-A" }],
      "proxy-groups": [{ name: "Google", type: "select", proxies: ["TW-A"] }],
      listeners: [{ type: "socks", port: 7892, proxy: "Google" }],
      rules: ["MATCH,DIRECT"]
    });
    assert(groupByName(output, "Google"), "legacy managed listener alias must survive compact mode");
    assert.strictEqual(output.listeners[0].proxy, "Google", "legacy listener alias must keep its target name");
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

// 规则指向的地区组可能不存在（订阅里没有对应地区的节点）：目标必须降级到兜底组，
// 否则 mihomo 会因 proxy [SG] not found 拒绝整份配置（发布包实测过）。
{
  const logs = [];
  const originalLog = console.log;
  let output;
  console.log = (...args) => { logs.push(args.join(" ")); };
  try {
    output = run({
      proxies: [{ name: "HKG-01" }, { name: "US-01" }],
      "proxy-groups": [],
      rules: [
        "DOMAIN-SUFFIX,dola.com,SG",
        "DOMAIN-SUFFIX,wjkc.xyz,TW",
        "DOMAIN-SUFFIX,lexmount.com,US",
        "MATCH,DIRECT"
      ]
    });
  } finally {
    console.log = originalLog;
  }

  assert(!groupByName(output, "SG"), "订阅无新加坡节点时不应生成 SG 组");
  assert(!groupByName(output, "TW"), "订阅无台湾节点时不应生成 TW 组");
  assert(output.rules.includes("DOMAIN-SUFFIX,dola.com,Proxies"), "指向缺失 SG 组的规则必须降级到 Proxies");
  assert(output.rules.includes("DOMAIN-SUFFIX,wjkc.xyz,Proxies"), "指向缺失 TW 组的规则必须降级到 Proxies");
  assert(output.rules.includes("DOMAIN-SUFFIX,lexmount.com,US"), "US 兜底组始终存在，目标不应被动");
  assert(logs.some((line) => line.includes("兜底组")), "降级必须打日志告知用户");
}

// 有对应地区节点时目标保持原样（不得误降级）
{
  const output = run({
    proxies: [{ name: "新加坡 01" }, { name: "台湾 01" }],
    "proxy-groups": [],
    rules: ["DOMAIN-SUFFIX,dola.com,SG", "DOMAIN-SUFFIX,wjkc.xyz,TW", "MATCH,DIRECT"]
  });

  assert(groupByName(output, "SG"), "订阅有新加坡节点时必须生成 SG 组");
  assert(groupByName(output, "TW"), "订阅有台湾节点时必须生成 TW 组");
  assert(output.rules.includes("DOMAIN-SUFFIX,dola.com,SG"), "SG 组存在时目标必须保持 SG");
  assert(output.rules.includes("DOMAIN-SUFFIX,wjkc.xyz,TW"), "TW 组存在时目标必须保持 TW");
}

// sub-rule 列表里的地区组目标同样兜底
{
  const output = run({
    proxies: [{ name: "US-01" }],
    "proxy-groups": [],
    "sub-rules": { custom: ["DOMAIN-SUFFIX,dola.com,SG"] },
    rules: ["SUB-RULE,(NETWORK,TCP),custom", "MATCH,DIRECT"]
  });

  assert.deepStrictEqual(
    output["sub-rules"].custom,
    ["DOMAIN-SUFFIX,dola.com,Proxies"],
    "sub-rule 内的地区组目标同样必须降级"
  );
}

// 订阅自建同名组且未被压缩时，组仍在，目标不得被动（防过度降级）
{
  const output = run({
    proxies: [{ name: "US-01" }],
    "proxy-groups": [
      { name: "SG", type: "select", proxies: ["US-01"] },
      { name: "Custom", type: "select", proxies: ["SG"] }
    ],
    rules: ["DOMAIN-SUFFIX,example.test,Custom", "DOMAIN-SUFFIX,dola.com,SG", "MATCH,DIRECT"]
  });

  assert(groupByName(output, "SG"), "非压缩模式下订阅自建 SG 组必须保留");
  assert(output.rules.includes("DOMAIN-SUFFIX,dola.com,SG"), "目标组存在时不得降级");
}

// Keep valid subscription inputs beside their assertions so the same fixtures also
// run through the real kernel below. A passing JS transform alone is not enough.
const safetyProxy = (name, extra = {}) => ({
  name, type: "http", server: "127.0.0.1", port: 18080, ...extra
});
const mappingCases = ["lowercase", "node-collision", "provider-collision"].map(kind => {
  const lowerName = unifiedGoogleGroup.toLowerCase();
  const actualName = kind === "lowercase" ? lowerName : unifiedGoogleGroup + " Group";
  const config = {
    proxies: [safetyProxy("US-A"), safetyProxy("TW-A")],
    "proxy-groups": kind === "lowercase" ? [{ name: lowerName, type: "select", proxies: ["TW-A"] }] : [],
    rules: [`DOMAIN,google.example,${unifiedGoogleGroup}`, "MATCH,DIRECT"],
    "sub-rules": { custom: [`AND,((DOMAIN,sub.test),(NETWORK,TCP)),${unifiedGoogleGroup.toUpperCase()}`] },
    "rule-providers": { custom: { type: "inline", behavior: "domain", payload: [], proxy: unifiedGoogleGroup } }
  };
  if (kind === "node-collision") config.proxies.push(safetyProxy(unifiedGoogleGroup));
  if (kind === "provider-collision") config["proxy-providers"] = { [unifiedGoogleGroup]: { type: "inline", payload: [safetyProxy("US-provider")] } };
  return {
    name: `P2 unified group mapping: ${kind}`, config,
    check(output) {
      assert(groupByName(output, actualName));
      assert(output.rules.includes(`DOMAIN,google.example,${actualName}`), "P2: canonical group name must map to the actual group, not a same-named node");
      assert.strictEqual(output["rule-providers"].custom.proxy, actualName);
      assert.deepStrictEqual(output["sub-rules"].custom, [`AND,((DOMAIN,sub.test),(NETWORK,TCP)),${actualName}`]);
      assert.strictEqual(output["proxy-groups"].filter(group => group.name === actualName).length, 1);
    }
  };
});
for (const testCase of mappingCases) testCase.check(run(testCase.config));

const safetyCases = [
  {
    name: "P1 transitive alias cycle",
    config: {
      proxies: [safetyProxy("US-A"), safetyProxy("TW-A")],
      "proxy-groups": [
        { name: "Google", type: "select", proxies: ["TW-A"] },
        { name: "Daily", type: "select", proxies: ["Google"] },
        { name: "Safe", type: "select", proxies: ["US-A"] }
      ],
      rules: ["DOMAIN,example.test,Daily", "MATCH,DIRECT"]
    },
    verify(output) {
      assert(!groupByName(output, "Proxies").proxies.includes("Daily"), "P1: transitive back-edge must be removed");
      assert(groupByName(output, "Proxies").proxies.includes("Safe"), "unrelated custom options must survive");
      assert.deepStrictEqual(groupByName(output, "Daily").proxies, ["Google"]);
      assert.deepStrictEqual(groupByName(output, "Google").proxies, [unifiedGoogleGroup]);
    }
  },
  {
    name: "P1 region alias cycle without a Proxies edge",
    config: {
      proxies: [safetyProxy("US-A"), safetyProxy("HK-A")],
      "proxy-groups": [
        { name: "Google", type: "select", proxies: ["HK-A"] },
        { name: "Hong Kong Daily", type: "select", proxies: ["Google"] }
      ],
      rules: ["DOMAIN,example.test,Hong Kong Daily", "MATCH,DIRECT"]
    },
    verify(output) {
      assert(!groupByName(output, unifiedGoogleGroup).proxies.includes("HK"), "P1: unified group must not loop through a regional alias");
    }
  },
  {
    name: "P1 removed info node references and empty group",
    config: {
      proxies: [safetyProxy("Traffic 100GB"), safetyProxy("US-A", { "dialer-proxy": "Traffic 100GB" })],
      "proxy-groups": [
        { name: "Custom", type: "select", proxies: ["Traffic 100GB", "US-A"] },
        { name: "Info Only", type: "select", proxies: ["Traffic 100GB"] }
      ],
      "rule-providers": { custom: { type: "inline", behavior: "domain", payload: [], proxy: "Traffic 100GB" } },
      "proxy-providers": { airport: { type: "inline", payload: [safetyProxy("US-remote", { "dialer-proxy": "Traffic 100GB" })] } },
      "sub-rules": { sub: ["DOMAIN,sub.test,Traffic 100GB"] },
      listeners: [{ name: "info-listener", type: "socks", port: 18090, proxy: "Traffic 100GB" }],
      rules: ["DOMAIN,example.test,Custom", "DOMAIN,info.test,Info Only", "DOMAIN,target.test,Traffic 100GB", "MATCH,DIRECT"]
    },
    verify(output) {
      assert.deepStrictEqual(output.proxies.map(p => p.name), ["US-A"]);
      assert.deepStrictEqual(groupByName(output, "Custom").proxies, ["US-A"], "P1: retained groups must drop removed nodes");
      assert.deepStrictEqual(groupByName(output, "Info Only").proxies, ["REJECT"], "P1: emptied groups must fail closed");
      assert.strictEqual(output.proxies[0]["dialer-proxy"], "REJECT");
      assert.strictEqual(output.listeners[0].proxy, "REJECT");
      assert.strictEqual(output["rule-providers"].custom.proxy, "REJECT");
      assert.strictEqual(output["proxy-providers"].airport.payload[0]["dialer-proxy"], "REJECT");
      assert(output.rules.includes("DOMAIN,target.test,REJECT"));
      assert.deepStrictEqual(output["sub-rules"].sub, ["DOMAIN,sub.test,REJECT"]);
    }
  },
  {
    name: "P1 restricted regions ignore mixed nested subscription groups",
    config: {
      proxies: [safetyProxy("US-A"), safetyProxy("HK-A"), safetyProxy("TW-A"), safetyProxy("SG-A"), safetyProxy("US HK ambiguous")],
      "proxy-groups": [
        { name: "US", type: "select", proxies: ["HK-A", "DIRECT", "US-A"] },
        { name: "TW", type: "url-test", proxies: ["US", "TW-A"] },
        { name: "SG", type: "fallback", proxies: ["DIRECT", "SG-A"] },
        { name: "Custom", type: "select", proxies: ["US", "TW", "SG"] }
      ],
      rules: ["DOMAIN,example.test,Custom", "MATCH,DIRECT"]
    },
    verify(output) {
      for (const region of ["US", "TW", "SG"]) {
        assert.deepStrictEqual(groupByName(output, region).proxies, [region + "-A"], "P1: only real, unambiguous region members are allowed");
        assert.strictEqual(groupByName(output, region).type, "select", "restricted regions must not automatically rotate nodes");
        assert.strictEqual(groupByName(output, region)["empty-fallback"], "REJECT");
      }
      assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US"]);
      assert.deepStrictEqual(groupByName(output, "Exchange").proxies, ["TW", "SG"]);
    }
  },
  {
    name: "P1 misleading US group without any US node",
    config: {
      proxies: [safetyProxy("HK-A")],
      "proxy-groups": [
        { name: "US", type: "select", proxies: ["DIRECT", "HK-A"] },
        { name: "Custom", type: "select", proxies: ["US"] }
      ],
      rules: ["DOMAIN,example.test,Custom", "MATCH,DIRECT"]
    },
    verify(output) {
      assert.deepStrictEqual(groupByName(output, "AI").proxies, ["REJECT"], "P1: a region group name is not proof of eligible nodes");
      assert.deepStrictEqual(groupByName(output, "US").proxies, ["REJECT"]);
      assert.deepStrictEqual(groupByName(run(output), "AI").proxies, ["REJECT"], "reapplying the script must not reclassify an empty US group");
    }
  },
  {
    name: "P1 mixed provider and region name collision",
    config: {
      proxies: [safetyProxy("US-local")],
      "proxy-providers": { US: { type: "inline", payload: [safetyProxy("US-remote")] } },
      "proxy-groups": [{ name: "US", type: "select", use: ["US"] }],
      rules: ["DOMAIN,example.test,US", "MATCH,DIRECT"]
    },
    verify(output) {
      assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US Group"]);
      assert.deepStrictEqual(groupByName(output, "US Group").use, ["US"]);
      assert.deepStrictEqual(groupByName(output, "US Group").proxies, ["US-local"]);
      assert(output.rules.includes("DOMAIN,example.test,US Group"));
    }
  },
  {
    name: "P1 provider restrictions with unsafe inherited options",
    config: {
      "proxy-providers": { airport: { type: "inline", payload: [safetyProxy("US-A"), safetyProxy("TW-A"), safetyProxy("SG-A"), safetyProxy("HK-A"), safetyProxy("US HK ambiguous"), safetyProxy("US Traffic 100GB")] } },
      "proxy-groups": [
        { name: "US", type: "url-test", use: ["airport"], filter: "US|HK", proxies: ["DIRECT"], "empty-fallback": "DIRECT", "include-all": true },
        { name: "TW", type: "select", use: ["airport"] },
        { name: "SG", type: "select", use: ["airport"] }
      ],
      rules: ["MATCH,DIRECT"]
    },
    verify(output) {
      for (const region of ["US", "TW", "SG"]) {
        const group = groupByName(output, region);
        assert.deepStrictEqual(group.proxies, [], "P1: no inherited groups or DIRECT in provider region groups");
        assert.deepStrictEqual(group.use, ["airport"]);
        assert.strictEqual(group.type, "select");
        assert.strictEqual(group["include-all"], undefined);
        assert.strictEqual(group["empty-fallback"], "REJECT", "P1: an empty provider filter must never become COMPATIBLE/DIRECT");
        const matches = group.filter.replace(/^\(\?i\)/, "");
        const excludes = group["exclude-filter"].replace(/^\(\?i\)/, "");
        const names = output["proxy-providers"].airport.payload.filter(p => new RegExp(matches, "i").test(p.name) && !new RegExp(excludes, "i").test(p.name)).map(p => p.name);
        assert.deepStrictEqual(names, [region + "-A"], "P1: provider filter must only admit eligible region nodes");
      }
    }
  }
];
for (const testCase of safetyCases) {
  testCase.verify(run(testCase.config));
}

// Download groups are transport dependencies, not business-routing choices.
const downloadCases = ["direct", "indirect", "collision", "dialer", "dynamic", "region", "provider-override", "provider-payload"].map(kind => {
  const config = {
    proxies: [safetyProxy("US-static")],
    "proxy-providers": {
      airport: { type: "inline", payload: [safetyProxy("TW-remote")], proxy: "Google" }
    },
    "proxy-groups": [{ name: "Google", type: "select", proxies: ["DIRECT", "US-static"], "default-selected": "DIRECT" }],
    rules: ["MATCH,DIRECT"]
  };
  if (kind === "indirect") {
    config["proxy-groups"].push(
      { name: "Download Root", type: "select", proxies: ["Download Middle", "DIRECT"], "default-selected": "Download Middle" },
      { name: "Download Middle", type: "select", proxies: ["Google"] }
    );
    config["proxy-providers"].airport.proxy = "Download Root";
    config["proxy-providers"].second = { ...config["proxy-providers"].airport };
  }
  if (kind === "collision") {
    config["proxy-groups"].push({ name: "Provider Download", type: "select", proxies: ["DIRECT"] });
    config.proxies.push(safetyProxy("Provider Download Group"));
    config["proxy-providers"]["Provider Download Group 2"] = { type: "inline", payload: [safetyProxy("HK-remote")] };
  }
  if (kind === "dialer") {
    config.proxies[0]["dialer-proxy"] = "Google";
    config["proxy-groups"][0].proxies = ["DIRECT"];
    config["proxy-providers"].airport.proxy = "US-static";
  }
  if (kind === "dynamic") {
    config["proxy-providers"].bootstrap = { type: "inline", payload: [safetyProxy("TW-bootstrap")] };
    Object.assign(config["proxy-groups"][0], { use: ["bootstrap"], filter: "TW|DIRECT", "exclude-filter": "HK", "empty-fallback": "REJECT" });
  }
  if (kind === "region") {
    config["proxy-groups"][0].name = "TW";
    config["proxy-providers"].airport.proxy = "TW";
  }
  if (kind === "provider-override" || kind === "provider-payload") {
    config["proxy-providers"].bootstrap = { type: "inline", payload: [safetyProxy("TW-bootstrap")] };
    const transport = kind === "provider-override" ?
      (config["proxy-providers"].bootstrap.override = {}) : config["proxy-providers"].bootstrap.payload[0];
    transport["dialer-proxy"] = "Google";
    config["proxy-groups"].push({ name: "Bootstrap", type: "select", use: ["bootstrap"] });
    config["proxy-providers"].airport.proxy = "Bootstrap";
  }
  return {
    name: "P2 provider download preservation: " + kind, config,
    verify(output) {
      let target = output["proxy-providers"].airport.proxy;
      if (kind === "dialer") {
        assert.strictEqual(target, "US-static", "download node names must stay stable for filters and selections");
        target = output.proxies.find(node => node.name === target)["dialer-proxy"];
      }
      const copiedRoot = groupByName(output, target);
      assert(copiedRoot && copiedRoot.hidden, "provider download must use a hidden copy of its original route");
      let copiedGoogle = copiedRoot;
      if (kind === "indirect") {
        assert.strictEqual(output["proxy-providers"].second.proxy, target, "providers sharing a route must share the same copy");
        assert.deepStrictEqual(groupByName(output, "Download Root").proxies, ["Download Middle", "DIRECT"], "shared original groups must remain untouched");
        assert.strictEqual(copiedRoot["default-selected"], copiedRoot.proxies[0], "default-selected must follow copied group names");
        copiedGoogle = groupByName(output, groupByName(output, copiedRoot.proxies[0]).proxies[0]);
      }
      if (kind === "provider-override" || kind === "provider-payload") {
        const bootstrap = output["proxy-providers"].bootstrap;
        const transport = kind === "provider-override" ? bootstrap.override : bootstrap.payload[0];
        copiedGoogle = groupByName(output, transport["dialer-proxy"]);
        assert.deepStrictEqual(copiedRoot.use, ["bootstrap"], "keep the existing source while preserving its declared transport dependency");
      }
      const expectedGoogle = { ...config["proxy-groups"][0], name: copiedGoogle.name, hidden: true };
      assert.deepStrictEqual(copiedGoogle, expectedGoogle, "preserve the original order, selection and dynamic source options");
      if (kind === "collision") assert.strictEqual(target, "Provider Download Group 3", "download copy names must avoid groups, nodes and providers");
      for (const name of ["AI", "Exchange", "US", "TW", "SG"]) {
        assert(!groupByName(output, name).proxies.some(option => /^Provider Download/.test(option)), "business and region groups must not offer download copies");
      }
      assert.deepStrictEqual(run(output), output, "repeated transforms must neither duplicate copies nor change download semantics");
    }
  };
});
for (const testCase of downloadCases) testCase.verify(run(testCase.config));
{
  const config = {
    "proxy-providers": { airport: { type: "inline", payload: [safetyProxy("TW-A")], proxy: "Custom Download" } },
    "proxy-groups": [{ name: "Custom Download", type: "select", proxies: ["DIRECT"] }],
    rules: ["MATCH,DIRECT"]
  };
  const output = run(config);
  assert.strictEqual(output["proxy-providers"].airport.proxy, "Custom Download", "unaffected download routes need no copies");
  assert(!output["proxy-groups"].some(group => /^Provider Download/.test(group.name)));
}

if (process.env.MIHOMO_BIN) {
  const httpProxy = (name, port, extra = {}) => ({
    name,
    type: "http",
    server: "127.0.0.1",
    port,
    ...extra
  });
  const mergeRules = mergeRulesFromYaml(mergeSource);
  assert(mergeRules.length > 100, "Merge.yaml must keep providing the routing rule set");
  const mergeProviders = mergeProviderStubs(mergeRules);

  const mihomoCases = [...downloadCases, ...safetyCases, ...mappingCases.map(testCase => ({
    name: testCase.name + " with actual Merge.yaml",
    config: {
      ...testCase.config,
      "rule-providers": { ...mergeProviders, ...testCase.config["rule-providers"] },
      rules: mergeRules.concat(testCase.config.rules)
    }
  })),
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
    },
    {
      name: "provider aliases do not create a proxy-group loop",
      config: {
        "proxy-providers": {
          airport: {
            type: "inline",
            payload: [httpProxy("US-A", 18088), httpProxy("TW-A", 18089)]
          }
        },
        "proxy-groups": [
          { name: "US", type: "url-test", use: ["airport"], filter: "US" },
          { name: "TW", type: "url-test", use: ["airport"], filter: "TW" },
          { name: "Google", type: "select", use: ["airport"], filter: "TW|US" },
          { name: "YouTube", type: "select", use: ["airport"], filter: "TW|US" },
          { name: "Telegram", type: "select", use: ["airport"], filter: "TW|US" }
        ],
        rules: ["MATCH,DIRECT"]
      }
    },
    {
      name: "merge rules with a subscription that has SG/TW nodes",
      config: {
        proxies: [httpProxy("新加坡 01", 18084), httpProxy("台湾 01", 18085)],
        "proxy-groups": [],
        "rule-providers": mergeProviders,
        rules: mergeRules.concat(["MATCH,DIRECT"])
      }
    },
    {
      name: "merge rules with a subscription that lacks SG/TW nodes",
      config: {
        proxies: [httpProxy("HKG-01", 18086), httpProxy("US-01", 18087)],
        "proxy-groups": [],
        "rule-providers": mergeProviders,
        rules: mergeRules.concat(["MATCH,DIRECT"])
      }
    }
  ];

  for (const testCase of mihomoCases) {
    if (testCase.verify) {
      const inputResult = childProcess.spawnSync(path.resolve(process.env.MIHOMO_BIN), [
        "-t", "-config", Buffer.from(JSON.stringify(testCase.config), "utf8").toString("base64")
      ], { encoding: "utf8" });
      assert.strictEqual(inputResult.status, 0, `${testCase.name} must start with a valid subscription:\n${inputResult.stdout}${inputResult.stderr}`);
    }
    const output = run(testCase.config);
    const encoded = Buffer.from(JSON.stringify(output), "utf8").toString("base64");
    const mihomoBin = path.resolve(process.env.MIHOMO_BIN);
    const result = childProcess.spawnSync(mihomoBin, ["-t", "-config", encoded], {
      encoding: "utf8"
    });
    assert.strictEqual(
      result.status,
      0,
      `${testCase.name} must pass Mihomo validation:\n` +
        `status=${result.status} signal=${result.signal} error=${result.error}\n` +
        `${result.stdout || ""}${result.stderr || ""}`
    );
  }
  console.log(`Mihomo configuration tests passed: ${mihomoCases.length}`);
}


{
  // 只有城市名、不带国名也不带旗帜的节点，必须也能归到正确地区。
  // 机场这么命名很常见，早先的正则只认国名缩写，会漏掉。
  const output = run({
    proxies: [
      { name: "Los Angeles 01" },
      { name: "大阪 02" },
      { name: "深港 03" },
      { name: "狮城 04" },
      { name: "台北 05" },
      { name: "伦敦 06" }
    ],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  assert.deepStrictEqual(groupByName(output, "US").proxies, ["Los Angeles 01"], "城市名要能识别成美国");
  assert.deepStrictEqual(groupByName(output, "JP").proxies, ["大阪 02"], "城市名要能识别成日本");
  assert.deepStrictEqual(groupByName(output, "HK").proxies, ["深港 03"], "机场缩写要能识别成香港");
  assert.deepStrictEqual(groupByName(output, "SG").proxies, ["狮城 04"], "「狮城」要能识别成新加坡");
  assert.deepStrictEqual(groupByName(output, "TW").proxies, ["台北 05"], "城市名要能识别成台湾");
  assert.deepStrictEqual(groupByName(output, "UK").proxies, ["伦敦 06"], "城市名要能识别成英国");
}

{
  // 机场直接用 IATA 三字码命名节点（HKG-01 / LAX-02 / NRT-03 …）：
  // 不识别的话这些节点不会进地区组，AI/Exchange 会整体退化成 REJECT。
  const output = run({
    proxies: [
      { name: "HKG-01" },
      { name: "NRT-02" },
      { name: "SIN-03" },
      { name: "TPE-04" },
      { name: "LAX-05" },
      { name: "LHR-06" }
    ],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  assert.deepStrictEqual(groupByName(output, "HK").proxies, ["HKG-01"], "IATA HKG 要能识别成香港");
  assert.deepStrictEqual(groupByName(output, "JP").proxies, ["NRT-02"], "IATA NRT 要能识别成日本");
  assert.deepStrictEqual(groupByName(output, "SG").proxies, ["SIN-03"], "IATA SIN 要能识别成新加坡");
  assert.deepStrictEqual(groupByName(output, "TW").proxies, ["TPE-04"], "IATA TPE 要能识别成台湾");
  assert.deepStrictEqual(groupByName(output, "US").proxies, ["LAX-05"], "IATA LAX 要能识别成美国");
  assert.deepStrictEqual(groupByName(output, "UK").proxies, ["LHR-06"], "IATA LHR 要能识别成英国");
}

{
  // 三字码必须按字母边界匹配：HKGX 这种名字不能被当成 HKG。
  const output = run({
    proxies: [{ name: "HKGX-99" }],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });
  assert(!groupByName(output, "HK"), "HKG 不能匹配 HKGX");
}

{
  // 提示类节点（剩余流量 / 套餐到期 / 官网…）必须被排除，不进任何组。
  // 它们的名字随订阅更新变化，选中会让出口 IP 漂到别处 —— 表现为 X 掉登录、
  // Discord 反复跳认证、AI 服务被风控，而且看不出是节点的问题。
  const output = run({
    proxies: [
      { name: "剩余流量：16.1 GB" },
      { name: "套餐到期：2026-09-10" },
      { name: "官网 example.com" },
      { name: "Traffic: 147.97 GB / 400 GB" },
      { name: "🇺🇸 US-A" }
    ],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  assert.deepStrictEqual(
    output.proxies.map((proxy) => proxy.name),
    ["🇺🇸 US-A"],
    "提示类节点不该出现在最终配置里"
  );
  assert.deepStrictEqual(groupByName(output, "US").proxies, ["🇺🇸 US-A"]);

  // 反过来：正常节点不能被误伤
  const keep = run({
    proxies: [{ name: "香港 01" }, { name: "US 直连备用" }],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });
  assert.deepStrictEqual(keep.proxies.map((proxy) => proxy.name), ["香港 01", "US 直连备用"]);
}


// 业务组必须遵循「地区优先」：第一个选项是明确的地区组，不能是兜底组 Proxies。
// 若把 Proxies 放回首位，该组的默认行为会退化成「跟随 Proxies 当前选中」，
// 分组形同虚设，且观察到的出口地区会变成 Proxies 选到什么的巧合。
{
  const output = run({
    proxies: [{ name: "香港 01" }, { name: "台湾 01" }, { name: "日本 01" }],
    "proxy-groups": [],
    rules: ["MATCH,DIRECT"]
  });

  const grp = groupByName(output, unifiedGoogleGroup);
  assert(grp, "Google + YouTube + Telegram 组必须生成");
  assert(!groupByName(output, "Google"), "新配置不应再生成独立 Google 组");
  assert(!groupByName(output, "YouTube"), "新配置不应再生成独立 YouTube 组");
  assert(!groupByName(output, "Telegram"), "新配置不应再生成独立 Telegram 组");
  assert.strictEqual(grp.proxies[0], "TW", "统一业务组有台湾节点时必须默认选择 TW");
  assert.notStrictEqual(
    grp.proxies[0],
    "Proxies",
    "统一业务组的首选必须是地区组，不能是兜底组 Proxies（否则默认行为退化为跟随兜底）"
  );
  assert(
    grp.proxies.includes("Proxies"),
    "统一业务组仍应保留 Proxies 选项（排在后面），以便需要时跟随全局"
  );
}

console.log("Script.js regression tests passed");

// A parser check cannot prove how provider filters behave after an update. Use a
// private core, loopback-only API, local file provider and no enabled proxy ports.
async function testProviderRuntime() {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "clash-safety-test-"));
  let core;
  let closed;
  let logs = "";
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  try {
    const fixture = safetyCases.find(item => item.name === "P1 provider restrictions with unsafe inherited options");
    const config = run(fixture.config);
    const providerFile = path.join(work, "airport.json");
    const writeProvider = proxies => fs.writeFileSync(providerFile, JSON.stringify({ proxies }));
    writeProvider(fixture.config["proxy-providers"].airport.payload.concat([{ name: "US Direct", type: "direct" }]));
    config["proxy-providers"].airport = { type: "file", path: providerFile, "health-check": { enable: false } };
    Object.assign(config, {
      "external-controller": "127.0.0.1:0", "log-level": "info",
      dns: { enable: false }, tun: { enable: false },
      profile: { "store-selected": false, "store-fake-ip": false }
    });
    core = childProcess.spawn(path.resolve(process.env.MIHOMO_BIN), [
      "-d", work, "-config", Buffer.from(JSON.stringify(config)).toString("base64")
    ]);
    closed = new Promise(resolve => core.once("close", resolve));
    core.stdout.on("data", data => { logs += data; });
    core.stderr.on("data", data => { logs += data; });
    core.on("error", error => { logs += error.message; });

    let address;
    for (let attempt = 0; attempt < 200; attempt++) {
      const match = /RESTful API listening at: (127\.0\.0\.1:\d+)/.exec(logs);
      if (match) { address = match[1]; break; }
      if (core.exitCode !== null || /External controller listen error/.test(logs)) break;
      await pause(50);
    }
    assert(address, `isolated test core must expose its loopback API:\n${logs}`);
    function request(endpoint, method = "GET") {
      return new Promise((resolve, reject) => {
        const req = http.request(`http://${address}${endpoint}`, { method, timeout: 3000 }, res => {
          let body = "";
          res.setEncoding("utf8");
          res.on("data", data => { body += data; });
          res.on("end", () => {
            if (res.statusCode >= 300) return reject(new Error(`${res.statusCode}: ${body}`));
            try { resolve(body ? JSON.parse(body) : null); } catch (error) { reject(error); }
          });
        });
        req.on("timeout", () => req.destroy(new Error("test API timed out")));
        req.on("error", reject);
        req.end();
      });
    }
    let state;
    for (let attempt = 0; attempt < 100; attempt++) {
      state = await request("/proxies");
      if (state.proxies.US && state.proxies.US.all.includes("US-A")) break;
      await pause(50);
    }
    for (const region of ["US", "TW", "SG"]) {
      assert.deepStrictEqual(state.proxies[region].all, [region + "-A"], "P1: actual core must exclude other regions, info nodes and direct proxies");
      assert.strictEqual(state.proxies[region].now, region + "-A");
    }
    writeProvider([safetyProxy("HK-A"), safetyProxy("US Traffic 100GB"), safetyProxy("US HK ambiguous")]);
    await request("/providers/proxies/airport", "PUT");
    state = await request("/proxies");
    for (const region of ["US", "TW", "SG"]) {
      assert.deepStrictEqual(state.proxies[region].all, ["REJECT"], "P1: provider losing the selected region must fail closed");
      assert.strictEqual(state.proxies[region].now, "REJECT");
    }
    writeProvider([safetyProxy("US-B"), safetyProxy("TW-B"), safetyProxy("SG-B")]);
    await request("/providers/proxies/airport", "PUT");
    state = await request("/proxies");
    for (const region of ["US", "TW", "SG"]) {
      assert.deepStrictEqual(state.proxies[region].all, [region + "-B"], "eligible nodes must return after provider recovery");
    }
    console.log("Mihomo provider runtime tests passed: initial / empty / recovered");
  } finally {
    if (core && core.pid) {
      core.kill("SIGTERM");
      const forceKill = setTimeout(() => core.kill("SIGKILL"), 3000);
      await closed;
      clearTimeout(forceKill);
    }
    fs.rmSync(work, { recursive: true, force: true });
  }
}

// No credentials, external websites, TUN or existing CVR state: a cold cache and
// a loopback HTTP server prove that a provider can actually bootstrap itself.
async function testProviderDownloadRuntime() {
  let fetches = 0;
  const server = http.createServer((req, res) => {
    fetches += 1;
    res.end(JSON.stringify({ proxies: [safetyProxy("TW-downloaded")] }));
  });
  const sockets = new Set();
  server.on("connect", (req, client, head) => {
    // The mock proxy only tunnels back to this same test server.
    if (req.url !== `127.0.0.1:${server.address().port}`) return client.destroy();
    const upstream = net.connect(server.address().port, "127.0.0.1", () => {
      client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
      if (head.length) upstream.write(head);
      client.pipe(upstream).pipe(client);
    });
    for (const socket of [client, upstream]) {
      sockets.add(socket);
      socket.on("close", () => sockets.delete(socket));
    }
    client.on("error", () => upstream.destroy());
    upstream.on("error", () => client.destroy());
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    for (const kind of ["direct", "indirect", "static-dialer", "provider-override", "provider-payload", "all-proxies", "all-providers"]) {
      const work = fs.mkdtempSync(path.join(os.tmpdir(), "clash-download-test-"));
      let core;
      let closed;
      let logs = "";
      try {
        const before = fetches;
        const input = {
          "proxy-providers": {
            airport: { type: "http", url: `http://127.0.0.1:${server.address().port}/nodes`, path: "./airport.json", proxy: kind === "indirect" ? "Download Root" : "Google", interval: 3600 }
          },
          "proxy-groups": [
            { name: "Proxies", type: "select", proxies: ["DIRECT"] },
            { name: "Google", type: "select", proxies: ["DIRECT"] },
            ...(kind === "indirect" ? [
              { name: "Download Root", type: "select", proxies: ["Download Middle"] },
              { name: "Download Middle", type: "select", proxies: ["Google"] }
            ] : [])
          ],
          rules: ["MATCH,DIRECT"]
        };
        if (kind === "static-dialer" || kind === "all-proxies") {
          input.proxies = [safetyProxy("Download transport", { port: server.address().port, "dialer-proxy": "Google" })];
          input["proxy-providers"].airport.proxy = "Download transport";
          if (kind === "all-proxies") {
            input["proxy-groups"].push({ name: "Bootstrap", type: "select", "include-all-proxies": true });
            input["proxy-providers"].airport.proxy = "Bootstrap";
          }
        }
        if (kind === "provider-override" || kind === "provider-payload" || kind === "all-providers") {
          const bootstrap = { type: "inline", payload: [safetyProxy("TW-bootstrap", { port: server.address().port })] };
          const transport = kind !== "provider-payload" ? (bootstrap.override = {}) : bootstrap.payload[0];
          transport["dialer-proxy"] = "Google";
          input["proxy-providers"].bootstrap = bootstrap;
          input["proxy-providers"].airport.proxy = "Bootstrap";
          input["proxy-groups"].push(kind === "all-providers" ?
            { name: "Bootstrap", type: "select", "include-all-providers": true, filter: "^TW-bootstrap$" } :
            { name: "Bootstrap", type: "select", use: ["bootstrap"] });
        }
        const config = run(input);
        Object.assign(config, {
          "external-controller": "127.0.0.1:0", "log-level": "info",
          dns: { enable: false }, tun: { enable: false },
          profile: { "store-selected": false, "store-fake-ip": false }
        });
        core = childProcess.spawn(path.resolve(process.env.MIHOMO_BIN), ["-d", work, "-config", Buffer.from(JSON.stringify(config)).toString("base64")]);
        closed = new Promise(resolve => core.once("close", resolve));
        core.stdout.on("data", data => { logs += data; });
        core.stderr.on("data", data => { logs += data; });
        core.on("error", error => { logs += error.message; });
        let state;
        for (let attempt = 0; attempt < 100; attempt++) {
          const match = /RESTful API listening at: (127\.0\.0\.1:\d+)/.exec(logs);
          if (match) {
            state = await new Promise((resolve, reject) => {
              const req = http.get(`http://${match[1]}/proxies`, { timeout: 3000 }, res => {
                let body = "";
                res.on("data", data => { body += data; });
                res.on("end", () => {
                  try { resolve(JSON.parse(body)); } catch (error) { reject(error); }
                });
              });
              req.on("timeout", () => req.destroy(new Error("download test API timed out")));
              req.on("error", reject);
            });
            if (state.proxies.TW && state.proxies.TW.all.includes("TW-downloaded")) break;
          }
          if (core.exitCode !== null || /initial proxy provider airport error/.test(logs)) break;
          await new Promise(resolve => setTimeout(resolve, 50));
        }
        assert(fetches > before, `cold HTTP provider must download through its preserved ${kind} route:\n${logs}`);
        assert(state && state.proxies.TW.all.includes("TW-downloaded"), `downloaded nodes must reach the actual core:\n${logs}`);
        assert.deepStrictEqual(state.proxies.US.all, ["REJECT"], "preserving downloads must not allow AI to use DIRECT or a non-US node");
        assert.deepStrictEqual(state.proxies.Exchange.all, ["TW", "SG"], "Exchange must retain its restricted regions");
      } finally {
        if (core && core.pid) {
          core.kill("SIGTERM");
          const forceKill = setTimeout(() => core.kill("SIGKILL"), 3000);
          await closed;
          clearTimeout(forceKill);
        }
        fs.rmSync(work, { recursive: true, force: true });
      }
    }
    console.log("Mihomo provider download tests passed: cold HTTP / indirect / static dialer / provider override+payload / include-all / fail-closed");
  } finally {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  }
}

if (process.env.MIHOMO_BIN) {
  testProviderRuntime().then(testProviderDownloadRuntime).catch(error => { console.error(error); process.exitCode = 1; });
}
