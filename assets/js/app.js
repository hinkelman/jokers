// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Browsers only let a page play sound after the player has interacted with it, so the audio
// context is created (or woken up) on the first click or key press.
let audio = null
let unlockAudio = () => {
  audio = audio || new AudioContext()
  if (audio.state === "suspended") audio.resume()
}
document.addEventListener("pointerdown", unlockAudio)
document.addEventListener("keydown", unlockAudio)

// one soft, short tone
let playTone = () => {
  if (!audio || audio.state !== "running") return
  let now = audio.currentTime
  let oscillator = audio.createOscillator()
  let gain = audio.createGain()
  oscillator.type = "sine"
  oscillator.frequency.value = 660
  gain.gain.setValueAtTime(0, now)
  gain.gain.linearRampToValueAtTime(0.15, now + 0.02)
  gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.6)
  oscillator.connect(gain).connect(audio.destination)
  oscillator.start(now)
  oscillator.stop(now + 0.6)
}

let Hooks = {}

// plays a tone when the turn passes to this page's player (but not when the page first loads)
Hooks.TurnAlert = {
  mounted() { this.myTurn = this.el.dataset.myTurn === "true" },
  updated() {
    let myTurn = this.el.dataset.myTurn === "true"
    if (myTurn && !this.myTurn) playTone()
    this.myTurn = myTurn
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

