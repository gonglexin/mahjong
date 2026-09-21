// 麻将音效：LiveView 推送 "play-sound" 事件，本 hook 用 Web Audio 播放。
// 音频文件位于 priv/static/sounds/。要换成长沙话真人语音时，
// 直接替换同名 mp3 文件即可，无需改动任何代码。
//
// 为什么用 Web Audio 而不是 Audio 元素：
//   * mp3 首次交互后统一解码成 AudioBuffer，播放零延迟、无网络请求
//   * 不受浏览器媒体元素数量上限约束，快速连响互不打断
//   * AudioContext 一次手势全局解锁，不存在逐元素自动播放竞态

const SOUND_FILES = {
  discard: "/sounds/discard.mp3", // 解除静音的反馈音
  chi: "/sounds/chi.mp3", // 吃
  peng: "/sounds/peng.mp3", // 碰
  gang: "/sounds/gang.mp3", // 杠
  zimo: "/sounds/zimo.mp3", // 自摸
  hu: "/sounds/hu.mp3", // 胡牌
  liuju: "/sounds/liuju.mp3", // 流局
}

// 出牌报牌名（如 wan5/tong3/tiao9）→ 牌面语音文件
const TILE_FILE_RE = /^(?:wan|tong|tiao)[1-9]$/

function soundSrc(name) {
  if (SOUND_FILES[name]) return SOUND_FILES[name]
  return TILE_FILE_RE.test(name) ? `/sounds/tiles/${name}.mp3` : null
}

// 全部音源名：7 个动作音 + 27 个牌面音
function allSoundNames() {
  const names = Object.keys(SOUND_FILES)
  for (const suit of ["wan", "tong", "tiao"]) for (let v = 1; v <= 9; v++) names.push(`${suit}${v}`)
  return names
}

const MUTE_KEY = "mahjong:sound-muted"

const SoundFX = {
  mounted() {
    this.ctx = null
    this.buffers = new Map() // name → AudioBuffer（已解码）
    this.loading = new Map() // name → Promise<AudioBuffer | null>
    this.muted = localStorage.getItem(MUTE_KEY) === "1"
    this.reflectMuted()

    this.handleEvent("play-sound", ({ name }) => this.play(name))

    const toggle = this.el.querySelector("[data-sound-toggle]")
    toggle.addEventListener("click", () => {
      this.muted = !this.muted
      localStorage.setItem(MUTE_KEY, this.muted ? "1" : "0")
      this.reflectMuted()
      // 解除静音时给一声轻响作为反馈
      if (!this.muted) this.play("discard")
    })

    // 浏览器自动播放策略：首次用户交互时创建并解锁 AudioContext
    const unlock = () => this.unlock()
    document.addEventListener("pointerdown", unlock, { once: true, capture: true })
    document.addEventListener("keydown", unlock, { once: true, capture: true })
  },

  unlock() {
    if (!this.ctx) {
      const Ctx = window.AudioContext || window.webkitAudioContext
      if (!Ctx) return
      this.ctx = new Ctx()
      for (const name of allSoundNames()) this.load(name)
    }
    if (this.ctx.state === "suspended") this.ctx.resume().catch(() => {})
  },

  load(name) {
    if (this.buffers.has(name) || this.loading.has(name)) return this.loading.get(name)

    const promise = fetch(soundSrc(name))
      .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.arrayBuffer()
      })
      .then(raw => this.decode(raw))
      .then(buffer => {
        this.buffers.set(name, buffer)
        this.loading.delete(name)
        return buffer
      })
      .catch(error => {
        console && console.warn(`[sound] ${name} 加载失败:`, error)
        this.loading.delete(name)
        return null
      })

    this.loading.set(name, promise)
    return promise
  },

  decode(raw) {
    // 兼容旧 Safari 的回调式 decodeAudioData
    return new Promise((resolve, reject) => this.ctx.decodeAudioData(raw, resolve, reject))
  },

  play(name) {
    if (!soundSrc(name) || this.muted) return
    this.unlock()
    if (!this.ctx) return

    const ready = this.buffers.get(name) || this.load(name)
    // 缓冲未就绪时等解码完成后补播；已就绪立即播
    Promise.resolve(ready)
      .then(buffer => buffer && this.start(buffer))
      .catch(() => {})
  },

  start(buffer) {
    if (this.muted || !this.ctx) return
    // 挂起状态下 start 的音源会在 context 恢复后立刻发声，不丢
    const source = this.ctx.createBufferSource()
    source.buffer = buffer
    source.connect(this.ctx.destination)
    source.start()
  },

  reflectMuted() {
    const toggle = this.el.querySelector("[data-sound-toggle]")
    if (toggle) toggle.setAttribute("data-muted", String(this.muted))
  },
}

export default SoundFX
