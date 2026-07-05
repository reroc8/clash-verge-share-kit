function main(config, profileName) {
  var groupNames = {};
  var groupNameByLower = {};
  var proxyNames = {};

  function normalizeName(name) {
    return String(name || "").toLowerCase();
  }

  function rememberGroupName(name) {
    if (!name) {
      return;
    }
    groupNames[name] = true;
    var lower = normalizeName(name);
    if (!groupNameByLower[lower]) {
      groupNameByLower[lower] = name;
    }
  }

  var ruleProviders = config["rule-providers"];
  if (ruleProviders && ruleProviders.reject) {
    delete ruleProviders.reject;
  }

  var rawGroups = Array.isArray(config["proxy-groups"]) ? config["proxy-groups"] : [];
  var groups = [];
  for (var i = 0; i < rawGroups.length; i++) {
    if (rawGroups[i] && rawGroups[i].name) {
      groups.push(rawGroups[i]);
      rememberGroupName(rawGroups[i].name);
    }
  }

  var rawProxies = Array.isArray(config.proxies) ? config.proxies : [];
  var proxies = [];
  for (var p = 0; p < rawProxies.length; p++) {
    if (rawProxies[p] && rawProxies[p].name) {
      proxies.push(rawProxies[p]);
      proxyNames[rawProxies[p].name] = true;
    }
  }
  config.proxies = proxies;

  function unique(items) {
    var seen = {};
    var result = [];
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      if (item && !seen[item]) {
        seen[item] = true;
        result.push(item);
      }
    }
    return result;
  }

  function findExistingGroup(name) {
    if (groupNames[name]) {
      return name;
    }
    return groupNameByLower[normalizeName(name)] || null;
  }

  function optionExists(name) {
    return name === "DIRECT" || name === "REJECT" || groupNames[name] || proxyNames[name];
  }

  function filterExisting(items) {
    var result = [];
    for (var i = 0; i < items.length; i++) {
      if (optionExists(items[i])) {
        result.push(items[i]);
      }
    }
    return unique(result);
  }

  function findGroup(name) {
    var existingName = findExistingGroup(name);
    if (!existingName) {
      return null;
    }
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] && groups[i].name === existingName) {
        return groups[i];
      }
    }
    return null;
  }

  function ensureGroup(name, options) {
    var existingName = findExistingGroup(name);
    if (existingName) {
      return existingName;
    }
    var finalOptions = filterExisting(options);
    if (finalOptions.length === 0) {
      finalOptions = ["DIRECT"];
    }
    groups.push({
      name: name,
      type: "select",
      proxies: finalOptions
    });
    rememberGroupName(name);
    return name;
  }

  function ensureManagedGroup(name, options, fallbackOptions) {
    var existingGroup = findGroup(name);
    var finalOptions = filterExisting(options);
    if (finalOptions.length === 0) {
      finalOptions = filterExisting(fallbackOptions || ["DIRECT"]);
    }
    if (finalOptions.length === 0) {
      finalOptions = ["DIRECT"];
    }
    if (existingGroup) {
      existingGroup.type = "select";
      existingGroup.proxies = finalOptions;
      return existingGroup.name;
    }
    return ensureGroup(name, finalOptions);
  }

  function optionMatches(name, patterns) {
    for (var i = 0; i < patterns.length; i++) {
      if (patterns[i].test(name)) {
        return true;
      }
    }
    return false;
  }

  var originalGroups = [];
  for (var g = 0; g < groups.length; g++) {
    originalGroups.push(groups[g].name);
  }

  var originalProxies = [];
  for (var pr = 0; pr < proxies.length; pr++) {
    originalProxies.push(proxies[pr].name);
  }
  var compactGroupsEnabled = originalProxies.length > 0;

  var preferredGeneralGroups = [
    "节点选择",
    "代理",
    "代理选择",
    "手动切换",
    "自动选择",
    "故障转移",
    "Proxy",
    "Proxy Select",
    "GLOBAL",
    "Global",
    "Auto",
    "Fallback"
  ];

  var generalOptions = [];
  if (!compactGroupsEnabled) {
    for (var pg = 0; pg < preferredGeneralGroups.length; pg++) {
      if (groupNames[preferredGeneralGroups[pg]]) {
        generalOptions.push(preferredGeneralGroups[pg]);
      }
    }
    generalOptions = generalOptions.concat(originalGroups);
  }
  generalOptions = generalOptions.concat(originalProxies).concat(["DIRECT"]);

  var PROXIES_GROUP = ensureManagedGroup("Proxies", generalOptions, ["DIRECT"]);

  var regionPatterns = {
    HK: [/香港/i, /Hong Kong/i, /(^|[^A-Za-z])HK([^A-Za-z]|$)/i, /🇭🇰/],
    JP: [/日本/i, /Japan/i, /Tokyo/i, /Osaka/i, /(^|[^A-Za-z])JP([^A-Za-z]|$)/i, /🇯🇵/],
    SG: [/新加坡/i, /Singapore/i, /(^|[^A-Za-z])SG([^A-Za-z]|$)/i, /🇸🇬/],
    TW: [/台湾/i, /台灣/i, /臺灣/i, /Taiwan/i, /(^|[^A-Za-z])TW([^A-Za-z]|$)/i, /🇹🇼/],
    US: [/美国/i, /美國/i, /United States/i, /America/i, /(^|[^A-Za-z])US([^A-Za-z]|$)/i, /(^|[^A-Za-z])USA([^A-Za-z]|$)/i, /🇺🇸/]
  };

  var managedGroups = {
    Proxies: PROXIES_GROUP
  };
  var detectedRegions = {};

  var regionOrder = ["HK", "JP", "SG", "TW", "US"];
  for (var ro = 0; ro < regionOrder.length; ro++) {
    var region = regionOrder[ro];
    var regionOptions = [];
    var patterns = regionPatterns[region];

    if (!compactGroupsEnabled) {
      for (var og = 0; og < originalGroups.length; og++) {
        if (optionMatches(originalGroups[og], patterns)) {
          regionOptions.push(originalGroups[og]);
        }
      }
    }
    for (var op = 0; op < originalProxies.length; op++) {
      if (optionMatches(originalProxies[op], patterns)) {
        regionOptions.push(originalProxies[op]);
      }
    }

    if (regionOptions.length > 0) {
      detectedRegions[region] = true;
      managedGroups[region] = ensureManagedGroup(region, regionOptions, ["DIRECT"]);
    }
  }

  if (!managedGroups.US) {
    managedGroups.US = ensureManagedGroup("US", [PROXIES_GROUP, "DIRECT"], ["DIRECT"]);
  }
  managedGroups.Claude = ensureManagedGroup("Claude", [
    detectedRegions.US ? managedGroups.US : null
  ], ["REJECT"]);
  managedGroups.AI = ensureManagedGroup("AI", [
    detectedRegions.US ? managedGroups.US : null,
    detectedRegions.TW ? managedGroups.TW : null
  ], ["REJECT"]);
  managedGroups.Google = ensureManagedGroup("Google", [PROXIES_GROUP, managedGroups.US, managedGroups.HK, managedGroups.JP, managedGroups.SG, managedGroups.TW, "DIRECT"], ["DIRECT"]);
  managedGroups.YouTube = ensureManagedGroup("YouTube", [PROXIES_GROUP, managedGroups.HK, managedGroups.JP, managedGroups.SG, managedGroups.TW, managedGroups.US, "DIRECT"], ["DIRECT"]);
  managedGroups.Telegram = ensureManagedGroup("Telegram", [PROXIES_GROUP, managedGroups.HK, managedGroups.JP, managedGroups.SG, managedGroups.TW, managedGroups.US], [PROXIES_GROUP]);
  managedGroups.Exchange = ensureManagedGroup("Exchange", [managedGroups.TW, managedGroups.SG], ["REJECT"]);

  var managedTargetMap = {};
  for (var managedName in managedGroups) {
    if (managedGroups.hasOwnProperty(managedName)) {
      managedTargetMap[managedName] = managedGroups[managedName];
    }
  }

  if (compactGroupsEnabled) {
    var keepGroupNames = {};
    for (var keepName in managedTargetMap) {
      if (managedTargetMap.hasOwnProperty(keepName)) {
        keepGroupNames[managedTargetMap[keepName]] = true;
      }
    }

    var compactGroups = [];
    var compactSeen = {};
    for (var cg = 0; cg < groups.length; cg++) {
      var compactGroup = groups[cg];
      if (compactGroup && keepGroupNames[compactGroup.name] && !compactSeen[compactGroup.name]) {
        compactGroups.push(compactGroup);
        compactSeen[compactGroup.name] = true;
      }
    }
    groups = compactGroups;
  }

  var displayGroupOrder = [
    managedGroups.Claude,
    managedGroups.AI,
    managedGroups.Google,
    managedGroups.YouTube,
    managedGroups.Telegram,
    managedGroups.Exchange,
    managedGroups.US,
    managedGroups.TW,
    managedGroups.SG,
    managedGroups.HK,
    managedGroups.JP,
    PROXIES_GROUP
  ];
  var orderedGroups = [];
  var orderedSeen = {};
  function appendGroupByName(name) {
    if (!name || orderedSeen[name]) {
      return;
    }
    for (var ag = 0; ag < groups.length; ag++) {
      if (groups[ag] && groups[ag].name === name) {
        orderedGroups.push(groups[ag]);
        orderedSeen[name] = true;
        return;
      }
    }
  }
  for (var og = 0; og < displayGroupOrder.length; og++) {
    appendGroupByName(displayGroupOrder[og]);
  }
  for (var rg = 0; rg < groups.length; rg++) {
    if (groups[rg] && groups[rg].name && !orderedSeen[groups[rg].name]) {
      orderedGroups.push(groups[rg]);
      orderedSeen[groups[rg].name] = true;
    }
  }
  groups = orderedGroups;

  config["proxy-groups"] = groups;

  function rewriteRuleTarget(rule) {
    if (typeof rule !== "string" || rule.indexOf("(") !== -1) {
      return rule;
    }
    var parts = rule.split(",");
    if (parts.length < 2) {
      return rule;
    }
    var targetIndex = parts[0] === "MATCH" ? 1 : 2;
    if (parts.length > targetIndex && managedTargetMap[parts[targetIndex]]) {
      parts[targetIndex] = managedTargetMap[parts[targetIndex]];
      return parts.join(",");
    }
    return rule;
  }

  var exchangeDomains = [
    "okx.com",
    "okx-dns.com",
    "okex.com",
    "oklink.com",
    "bybit.com",
    "bybitglobal.com",
    "bybit.cloud",
    "bycsi.com",
    "bytick.com",
    "binance.com",
    "binance.info",
    "binance.me",
    "binance.us",
    "binancecnt.com",
    "bnbstatic.com",
    "bitget.com",
    "bitgetimg.com",
    "bitgetstatic.com",
    "gate.com",
    "gate.io",
    "gateimg.com",
    "kucoin.com",
    "kucoin.plus",
    "kucoin.cloud",
    "mexc.com",
    "mexc.co",
    "mexc.fm",
    "crypto.com",
    "coinbase.com",
    "coinbasecdn.net",
    "kraken.com",
    "krakenassets.com",
    "htx.com",
    "huobi.com",
    "huobi.pro",
    "bingx.com",
    "bitmart.com",
    "bitfinex.com",
    "bitstamp.net",
    "upbit.com"
  ];

  var exchangeDomainSet = {};
  for (var k = 0; k < exchangeDomains.length; k++) {
    exchangeDomainSet[exchangeDomains[k]] = true;
  }

  function isManagedExchangeRule(rule) {
    if (typeof rule !== "string" || rule.indexOf("(") !== -1) {
      return false;
    }
    var parts = rule.split(",");
    return parts[0] === "DOMAIN-SUFFIX" && exchangeDomainSet[parts[1]] === true;
  }

  function isRejectRule(rule) {
    if (typeof rule !== "string" || rule.indexOf("(") !== -1) {
      return false;
    }
    var parts = rule.split(",");
    if (parts.length < 2) {
      return false;
    }
    var type = String(parts[0] || "").toUpperCase();
    var targetIndex = type === "MATCH" ? 1 : 2;
    var providerName = String(parts[1] || "").toLowerCase();
    var target = String(parts[targetIndex] || "").toUpperCase();
    return target === "REJECT" || (type === "RULE-SET" && providerName === "reject");
  }

  var exchangeRules = [];
  for (var er = 0; er < exchangeDomains.length; er++) {
    exchangeRules.push("DOMAIN-SUFFIX," + exchangeDomains[er] + "," + managedGroups.Exchange);
  }

  var rules = config.rules || [];
  var cleanedRules = [];
  for (var r = 0; r < rules.length; r++) {
    var rewrittenRule = rewriteRuleTarget(rules[r]);
    if (!isManagedExchangeRule(rewrittenRule) && !isRejectRule(rewrittenRule)) {
      cleanedRules.push(rewrittenRule);
    }
  }

  function isBroadRule(rule) {
    if (typeof rule !== "string") {
      return false;
    }
    var upperRule = rule.toUpperCase();
    var broadRules = [
      "RULE-SET,GFW,",
      "RULE-SET,GREATFIRE,",
      "RULE-SET,TLD-NOT-CN,",
      "RULE-SET,PROXY,",
      "RULE-SET,DIRECT,",
      "RULE-SET,APPLICATIONS,",
      "RULE-SET,CNCIDR,",
      "GEOIP,",
      "GEOSITE,",
      "MATCH,",
      "FINAL,"
    ];

    for (var y = 0; y < broadRules.length; y++) {
      if (upperRule.indexOf(broadRules[y]) === 0) {
        return true;
      }
    }

    return upperRule.indexOf("IP-CIDR,0.0.0.0/0,") === 0 ||
      upperRule.indexOf("IP-CIDR6,::/0,") === 0;
  }

  var insertAt = -1;
  for (var x = 0; x < cleanedRules.length; x++) {
    if (isBroadRule(cleanedRules[x])) {
      insertAt = x;
      break;
    }
  }

  if (insertAt === -1) {
    insertAt = 0;
  }

  cleanedRules.splice.apply(cleanedRules, [insertAt, 0].concat(exchangeRules));
  config.rules = cleanedRules;

  return config;
}
