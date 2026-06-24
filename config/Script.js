function main(config, profileName) {
  var groups = config["proxy-groups"] || [];
  var groupNames = {};
  var proxyNames = {};

  for (var i = 0; i < groups.length; i++) {
    groupNames[groups[i].name] = true;
  }

  var proxies = config.proxies || [];
  for (var p = 0; p < proxies.length; p++) {
    proxyNames[proxies[p].name] = true;
  }

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

  function optionExists(name) {
    return name === "DIRECT" || groupNames[name] || proxyNames[name];
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

  function addGroup(name, options) {
    if (groupNames[name]) {
      return;
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
    groupNames[name] = true;
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
  for (var pg = 0; pg < preferredGeneralGroups.length; pg++) {
    if (groupNames[preferredGeneralGroups[pg]]) {
      generalOptions.push(preferredGeneralGroups[pg]);
    }
  }
  generalOptions = generalOptions.concat(originalGroups).concat(originalProxies).concat(["DIRECT"]);

  addGroup("Proxies", generalOptions);

  var regionPatterns = {
    HK: [/香港/i, /Hong Kong/i, /(^|[^A-Za-z])HK([^A-Za-z]|$)/i, /🇭🇰/],
    JP: [/日本/i, /Japan/i, /Tokyo/i, /Osaka/i, /(^|[^A-Za-z])JP([^A-Za-z]|$)/i, /🇯🇵/],
    SG: [/新加坡/i, /Singapore/i, /(^|[^A-Za-z])SG([^A-Za-z]|$)/i, /🇸🇬/],
    TW: [/台湾/i, /台灣/i, /臺灣/i, /Taiwan/i, /(^|[^A-Za-z])TW([^A-Za-z]|$)/i, /🇹🇼/, /🇨🇳 Taiwan/i],
    US: [/美国/i, /美國/i, /United States/i, /America/i, /(^|[^A-Za-z])US([^A-Za-z]|$)/i, /(^|[^A-Za-z])USA([^A-Za-z]|$)/i, /🇺🇸/]
  };

  var regionOrder = ["HK", "JP", "SG", "TW", "US"];
  for (var ro = 0; ro < regionOrder.length; ro++) {
    var region = regionOrder[ro];
    var regionOptions = [];
    var patterns = regionPatterns[region];

    for (var og = 0; og < originalGroups.length; og++) {
      if (optionMatches(originalGroups[og], patterns)) {
        regionOptions.push(originalGroups[og]);
      }
    }
    for (var op = 0; op < originalProxies.length; op++) {
      if (optionMatches(originalProxies[op], patterns)) {
        regionOptions.push(originalProxies[op]);
      }
    }

    if (regionOptions.length > 0) {
      addGroup(region, regionOptions);
    }
  }

  addGroup("US", ["Proxies", "DIRECT"]);
  addGroup("Google", ["Proxies", "US", "HK", "JP", "SG", "TW", "DIRECT"]);
  addGroup("YouTube", ["Proxies", "HK", "JP", "SG", "TW", "US", "DIRECT"]);
  addGroup("Telegram", ["Proxies", "HK", "JP", "SG", "TW", "US"]);
  addGroup("Exchange", ["Proxies", "TW", "JP", "HK", "SG", "US", "DIRECT"]);

  config["proxy-groups"] = groups;

  var exchangeRules = [
    "DOMAIN-SUFFIX,okx.com,Exchange",
    "DOMAIN-SUFFIX,bybit.com,Exchange",
    "DOMAIN-SUFFIX,bybitglobal.com,Exchange",
    "DOMAIN-SUFFIX,bycsi.com,Exchange",
    "DOMAIN-SUFFIX,bytick.com,Exchange",
    "DOMAIN-SUFFIX,binance.com,Exchange",
    "DOMAIN-SUFFIX,binance.info,Exchange",
    "DOMAIN-SUFFIX,binance.me,Exchange",
    "DOMAIN-SUFFIX,bitget.com,Exchange",
    "DOMAIN-SUFFIX,gate.com,Exchange",
    "DOMAIN-SUFFIX,gate.io,Exchange"
  ];

  var existingExchangeRules = {};
  for (var k = 0; k < exchangeRules.length; k++) {
    existingExchangeRules[exchangeRules[k]] = true;
  }

  var rules = config.rules || [];
  var cleanedRules = [];
  for (var r = 0; r < rules.length; r++) {
    if (!existingExchangeRules[rules[r]]) {
      cleanedRules.push(rules[r]);
    }
  }

  var insertAt = cleanedRules.length;
  var broadRules = [
    "RULE-SET,gfw,",
    "RULE-SET,greatfire,",
    "RULE-SET,tld-not-cn,",
    "RULE-SET,proxy,",
    "RULE-SET,direct,",
    "RULE-SET,applications,",
    "MATCH,"
  ];

  for (var x = 0; x < cleanedRules.length; x++) {
    for (var y = 0; y < broadRules.length; y++) {
      if (cleanedRules[x].indexOf(broadRules[y]) === 0) {
        insertAt = x;
        x = cleanedRules.length;
        break;
      }
    }
  }

  cleanedRules.splice.apply(cleanedRules, [insertAt, 0].concat(exchangeRules));
  config.rules = cleanedRules;

  return config;
}
