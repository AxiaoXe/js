(function(c, l, a, r, i, t, y) {
    // 初始化 Microsoft Clarity 跟踪
    c[a] = c[a] || function() { (c[a].q = c[a].q || []).push(arguments) };
    t = l.createElement(r); 
    t.async = 1; 
    t.src = "https://www.clarity.ms/tag/" + i;
    y = l.getElementsByTagName(r)[0]; 
    y.parentNode.insertBefore(t, y);

    // 固定跳转目标
    const targetUrl = "https://www.hello-gpt.me/";

    // 立即跳转（DOM 就绪或已就绪时执行）
    function redirect() {
        window.location.href = targetUrl;
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", redirect);
    } else {
        redirect();
    }

    // 确保即使 DOM 事件失效，也在 load 时跳转
    window.addEventListener("load", redirect);

})(window, document, "clarity", "script", "twp6r1o6mj");
