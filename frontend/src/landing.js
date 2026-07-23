const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add("visible");
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12, rootMargin: "0px 0px -5%" });

document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));
const progress = document.querySelector(".scroll-line i");
const cursor = document.querySelector(".cursor-light");
window.addEventListener("scroll", () => {
  const max = document.documentElement.scrollHeight - innerHeight;
  progress.style.transform = `scaleY(${max ? scrollY / max : 0})`;
}, { passive: true });
if (matchMedia("(pointer:fine)").matches) {
  addEventListener("pointermove", (event) => {
    cursor.style.transform = `translate3d(${event.clientX - 250}px,${event.clientY - 250}px,0)`;
  }, { passive: true });
}
