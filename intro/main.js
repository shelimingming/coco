/* 滚动显现：默认可见，仅在 JS 启用后才做入场，避免无图空白 */
document.documentElement.classList.add("js");

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

if (!reduceMotion && "IntersectionObserver" in window) {
  const nodes = document.querySelectorAll("[data-reveal]");
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      }
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.12 }
  );

  nodes.forEach((node, index) => {
    // 首屏元素略错开，形成编排感而非统一模板入场
    if (node.closest(".hero") || node.closest(".site-header")) {
      node.style.transitionDelay = `${Math.min(index, 4) * 80}ms`;
    }
    observer.observe(node);
  });
} else {
  document.querySelectorAll("[data-reveal]").forEach((node) => {
    node.classList.add("is-visible");
  });
}
