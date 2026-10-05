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

// The turn tone: one soft 660 Hz beep, fading out over 0.6 seconds, made here as a WAV file.
// It plays through an <audio> element rather than Web Audio because Safari silences Web Audio
// in background tabs, which is exactly where a player who's busy elsewhere will be.
let toneUrl = (() => {
  let rate = 44100
  let samples = rate * 0.6
  let view = new DataView(new ArrayBuffer(44 + samples * 2))
  let text = (offset, string) =>
    [...string].forEach((char, i) => view.setUint8(offset + i, char.charCodeAt(0)))
  text(0, "RIFF")
  view.setUint32(4, 36 + samples * 2, true)
  text(8, "WAVEfmt ")
  view.setUint32(16, 16, true) // format chunk size
  view.setUint16(20, 1, true) // PCM
  view.setUint16(22, 1, true) // mono
  view.setUint32(24, rate, true)
  view.setUint32(28, rate * 2, true) // bytes per second
  view.setUint16(32, 2, true) // bytes per sample
  view.setUint16(34, 16, true) // bits per sample
  text(36, "data")
  view.setUint32(40, samples * 2, true)
  for (let i = 0; i < samples; i++) {
    let t = i / rate
    let envelope = Math.min(t / 0.02, 1) * Math.exp(-t * 8)
    view.setInt16(44 + i * 2, Math.sin(2 * Math.PI * 660 * t) * envelope * 0.3 * 32767, true)
  }
  return URL.createObjectURL(new Blob([view.buffer], {type: "audio/wav"}))
})()

let tone = new Audio(toneUrl)

// Browsers only let a page play sound once the player has interacted with it, and Safari only
// lets an audio element play by itself once it has been played from a click. So the first
// click or key press plays the tone silently, which lets it play later when the turn comes.
let unlocked = false
let unlockAudio = () => {
  if (unlocked) return
  unlocked = true
  tone.volume = 0
  tone.play()
    .then(() => {
      // unless the click was "Test sound", which wants to hear it
      if (tone.volume === 0) {
        tone.pause()
        tone.currentTime = 0
      }
    })
    .catch(() => { unlocked = false })
}
document.addEventListener("pointerdown", unlockAudio)
document.addEventListener("keydown", unlockAudio)

let playTone = () => {
  tone.volume = 1
  tone.currentTime = 0
  tone.play().catch(() => {})
}

// the "Test sound" link
window.addEventListener("jokers:test-tone", playTone)

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

