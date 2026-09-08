let progress = 0;
const progressBar = document.getElementById("progressBar");
const splashScreen = document.getElementById("splashScreen");
const loadingIndicators = document.querySelectorAll(".indicator");

let indicatorIndex = 0;
let splashHidden = false;

// Cycle the 3 loading dots
setInterval(() => {
    loadingIndicators.forEach(i => i.classList.remove("active"));
    if (loadingIndicators.length) {
        loadingIndicators[indicatorIndex % loadingIndicators.length].classList.add("active");
        indicatorIndex++;
    }
}, 400);

// Progress bar keeps climbing for as long as loading actually takes.
// It caps at 92% and waits — it does NOT control when the splash
// hides. Only Dart calling hideAppSplash() controls that.
const loadingInterval = setInterval(() => {
    progress += Math.floor(Math.random() * 4) + 1;
    if (progress >= 92) {
        progress = 92;
    }
    if (progressBar) {
        progressBar.style.width = progress + "%";
    }
}, 150);

// ---- THE KEY FIX ----
// This function is called FROM DART, only after your real loading
// work (session check, DB init, etc.) has actually finished. That
// is what makes the splash stay up for the full real loading time
// instead of vanishing the instant Flutter paints its first frame.
window.hideAppSplash = function () {
    if (splashHidden) return;
    splashHidden = true;

    clearInterval(loadingInterval);
    if (progressBar) {
        progressBar.style.width = "100%";
    }

    setTimeout(() => {
        if (splashScreen) {
            splashScreen.classList.add("hide");
            document.body.style.overflow = "auto";

            setTimeout(() => {
                splashScreen.remove();
            }, 500);
        }
    }, 200);
};

// Safety net only — if Dart never calls hideAppSplash for some
// reason (error, stuck request), don't leave the user stuck on the
// splash forever. Raise this if your real loading legitimately
// takes longer than 20s.
setTimeout(() => {
    if (!splashHidden) {
        window.hideAppSplash();
    }
}, 20000);

function startAgain() {
    window.location.reload();
}