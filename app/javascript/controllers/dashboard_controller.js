import { Controller } from "@hotwired/stimulus"

// Auto-refreshes the dashboard page using Turbo visit at a regular interval
export default class extends Controller {
  static values = { interval: { type: Number, default: 5000 } }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.timer = setInterval(() => {
      Turbo.visit(window.location.href, { action: "replace" })
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }
}
