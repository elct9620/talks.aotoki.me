---
theme: '@aotoki/slidev-theme-terraforming'
title: 微秒級的 Ruby 安全沙盒
hideInToc: true
mdc: true
routerMode: hash
layout: cover
---

# 讓 AI 接管你的應用

微秒級的 Ruby 安全沙盒

---
layout: center
---

<About>
  <Name>蒼時弦也</Name>
  <Title>Associate AI Engineer</Title>
  <Title>AI Engineer</Title>
  <Contact>https://blog.aotoki.me/</Contact>
  <Contact>@elct9620</Contact>
</About>

---

<Toc />

---
layout: section
---

# Why

為什麼需要一個 Ruby 沙盒？

---
hideInToc: true
layout: center
---

# For Next Generation

今年 Harness Engineering 已經被廣泛接受，我們需要跟不安全的程式碼共存

---
hideInToc: true
layout: center
---

# Ruby 語言準備好了嗎？

---
hideInToc: true
layout: diagram
---

<Map2D
  x-start="重"
  x-end="輕"
  y-start="黑名單"
  y-end="真隔離"
>
  <Point :x="18" :y="86">trusted-sandbox</Point>
  <Point :x="32" :y="70">ruby.wasm</Point>
  <Point :x="76" :y="44">mruby-engine</Point>
  <Point :x="60" :y="10">safe_ruby</Point>
  <Point :x="84" :y="16">Ruby::Box</Point>
</Map2D>

<Caption>Ruby 現有的選項。</Caption>

<!--
   這是 Ruby 的現況，隔離程度基本上是以邊界方式大致區分為主
-->

---
hideInToc: true
layout: center
---

# 沒有又快又安全的選項

---
hideInToc: true
layout: center
---

# Let's Build One

---
layout: section
---

# Demo

<!-- 說明會實際展示 -->

---
layout: section
---

# Design a Sandbox

從發揮 Ruby 語言特性開始思考

---
hideInToc: true
layout: center
---

# Cloudflare Workers 的體驗非常好，我們有機會嗎？

---
hideInToc: true
layout: statement
---

```ruby {all|1|3-4|6-9}
kv = KeyValueStore.new

sandbox = Sandbox.new
sandbox.bind("KV", kv)

sandbox.eval(<<~RUBY)
  KV.write("foo", "bar")
  KV.read("foo") # => "bar"
RUBY
```

---
hideInToc: true
layout: center
---

# Code Mode

讓 AI 自己寫程式查詢，就不用窮舉所有工具


---
hideInToc: true
layout: center
---

# Security

越少被利用的機會越安全，但跟容易使用互相衝突

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block name="proxy" color="tamago">代理</Block>

  <Stroke
    :dir="$clicks === 3 ? 'left' : 'right'"
    :label="$clicks === 1 ? '呼叫' : $clicks === 3 ? '結果' : ''"
    :labels="['呼叫', '結果']"
  />

  <Block name="object" color="gunJyo">物件</Block>

  <Focus :steps="['', 'proxy', 'object', 'proxy']" />
</Stage>

<Caption>
  <Line>透過代理物件，我們只知道能做什麼</Line>
  <Line>透過約定的方式傳輸參數</Line>
  <Line>真實的物件處理後，回傳結果</Line>
  <Line>只看到輸入跟輸出，背後完全黑箱</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block name="p1" color="gunJyo">Preview 1</Block>
  <Block name="p2" color="gunJyo">Preview 2</Block>
  <Block name="p3" color="gunJyo">Preview 3</Block>

  <Focus :steps="[null, 'p1', 'p2', 'p3', null]" />
</Stage>

<Caption>
  <Line>WASI 的標準，目前還沒穩定</Line>
  <Line>隔離性好，但功能很少且難用，目前 ruby.wasm 也還在用</Line>
  <Line>開始有擴充性，但會損失一些效能</Line>
  <Line>目前最新的標準，幾乎還沒有人用</Line>
  <Line>因為 Preview 1 完全無法擴充，改動 ruby.wasm 的成本太高</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block name="ruby" color="gunJyo">Ruby</Block>

  <Stroke
    :dir="$clicks === 2 ? 'left' : 'right'"
    :label="$clicks === 1 ? 'Exported' : $clicks === 2 ? 'Host' : ''"
    :labels="['Exported', 'Host']"
    :hidden="$clicks === 0"
  />

  <Block name="wasm" color="tamago">Wasm</Block>

  <Focus :steps="[null, 'wasm', 'ruby', null]" />
</Stage>

<Caption>
  <Line>WASM 虛擬機器原生就是隔離的</Line>
  <Line>透過 Exported Function 能讓 Wasm 的 C Function 被呼叫</Line>
  <Line>從 Wasm 呼叫外部的 C Function 叫做 Host Function</Line>
  <Line>能夠雙向溝通，就可以做很多事情</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block name="ruby" color="gunJyo">Ruby</Block>

  <Stroke
    :dir="$clicks >= 4 ? 'left' : 'right'"
    :label="$clicks === 1 ? 'Exported' : $clicks === 4 ? 'Host' : ''"
    :labels="['Exported', 'Host']"
  />

  <Block name="wasm" color="tamago">Wasm</Block>

  <Stroke
    :dir="$clicks >= 3 ? 'left' : 'right'"
    :label="$clicks === 2 ? 'eval' : $clicks === 3 ? 'return' : ''"
    :labels="['eval', 'return']"
  />

  <Block name="mruby" color="tamago">mruby</Block>

  <Focus :steps="[null, 'wasm', 'mruby', 'wasm', 'ruby', null]" />
</Stage>

<Caption>
  <Line>透過 Wasm 把 mruby 的記憶體隔離</Line>
  <Line>用 Export Function 呼叫 Wasm 裡面 Exported Function</Line>
  <Line>Wasm 呼叫 mrb_load_string 執行腳本</Line>
  <Line>mruby 把結果回傳給 Wasm</Line>
  <Line>Wasm 用 Host Function 通知 Ruby 執行結果</Line>
  <Line>Wasm 扮演中間人，保護兩邊</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<Stage column>
  <Block name="light" color="gunJyo">輕量</Block>

  <Stroke dir="down" />

  <Group>
    <Block name="compile" color="tamago">容易編譯</Block>
    <Block name="surface" color="tamago">攻擊面小</Block>
    <Block name="syntax" color="tamago">語法相容</Block>
  </Group>

  <Focus :steps="[null, 'compile', 'surface', 'syntax']" />
</Stage>

<Caption>
  <Line>mruby 的設計讓很多目標得以實現</Line>
  <Line>底層依賴少，編譯成 Wasm 幾乎不用處理</Line>
  <Line>核心功能精簡，能被利用來攻擊的路徑會變少</Line>
  <Line>使用 Ruby 相同的語法，使用體驗接近</Line>
</Caption>

---
hideInToc: true
layout: center
---

# Thin Core 哲學

Kobako 提供核心功能，但允許高度客製化

---
hideInToc: true
layout: center
---

# Transport

Kobako 為什麼能在不同記憶體架構，無縫轉換？

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block name="marshal" color="gunJyo">Marshal</Block>
  <Block name="json" color="gunJyo">JSON</Block>
  <Block name="protobuf" color="gunJyo">Protobuf</Block>
  <Block name="msgpack" color="gunJyo">MessagePack</Block>

  <Focus :steps="[null, 'marshal', 'json', 'protobuf', 'msgpack']" />
</Stage>

<Caption>
  <Line>利用序列化技術，轉換成雙方可理解的格式</Line>
  <Line>只有 CRuby 支援，Ruby 的標準序列化格式</Line>
  <Line>最通用且跨語言，但比較佔用記憶體和處理器</Line>
  <Line>格式固定，編碼跟解碼都很快，但無法動態定義</Line>
  <Line>用二進位格式表示的 JSON，事實上也更快更小</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block name="ruby" color="gunJyo">Ruby</Block>

  <Stroke
    dir="both"
    :label="$clicks >= 1 ? 'MessagePack' : ''"
    :labels="['MessagePack']"
    :hidden="$clicks === 0"
  />

  <Block name="mruby" color="tamago">mruby</Block>

  <Focus :steps="[null, null, ['ruby', 'mruby']]" />
</Stage>

<Caption>
  <Line>CRuby 和 mruby 的記憶體結構完全不同</Line>
  <Line>Kobako 定義交換格式的標準</Line>
  <Line>互相約定透過 MessagePack 溝通，就可以交換資料</Line>
</Caption>

---
layout: section
---

# Performance

Kobako 為什麼要跑得快？

---
hideInToc: true
layout: diagram
---

<Bars log axis-start="1ns" axis-end="1s" :steps="[null, 'ms', 'us', null]">
  <Bar :value="1000" text="1s" via="人類能感知">秒 s</Bar>
  <Bar name="ms" :value="1" text="1ms" via="打開網頁">毫秒 ms</Bar>
  <Bar name="us" :value="0.001" text="1µs" via="SSD 讀一次">微秒 µs</Bar>
  <Bar :value="0.000001" text="1ns" via="記憶體存取">奈秒 ns</Bar>
</Bars>

<Caption>
  <Line>每個單位差距一千倍，超過一秒使用者就會有等待的感覺</Line>
  <Line>一秒內人類幾乎不會覺得慢，大部分網路服務都是這個量級</Line>
  <Line>通常是作業系統等級的反應速度，每秒能處理上萬次</Line>
  <Line>反應速度影響使用起來是否會感到卡</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<!--
    基於 scripts/cold_start.rb 測試
-->

<Bars :steps="[null, 'recompile', 'cached', null]">
  <Bar name="recompile" :value="590" text="590ms">初次啟動</Bar>
  <Bar name="cached" :value="1.9" text="1.9ms">AOT 快取</Bar>
</Bars>

<Caption>
  <Line>利用快取讓冷啟動快一百倍</Line>
  <Line>Wasm 每次運行都需要編譯對應運行環境的版本</Line>
  <Line>未來啟動都從硬碟載入快取，不需要重新編譯</Line>
  <Line>透過快取減少重啟、初始化的啟動成本</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<!--
   wasmtime 的 InstancePre 會把連結結果快取起來，下一次 Sandbox.new 就不用再連結一次
-->

<Bars :steps="[null, 'relink', 'cached', null]">
  <Bar name="relink" :value="127" text="127µs">每次重新連結</Bar>
  <Bar name="cached" :value="4.14" text="4.1µs">連結結果快取</Bar>
</Bars>

<Caption>
  <Line>減少不必要的載入步驟</Line>
  <Line>啟動 Wasm 需要將 Exported / Host Function 重新連結</Line>
  <Line>每個環境都是相同的，把連結的結果快取到記憶體</Line>
  <Line>Host / Exported Functions 設計成無狀態，因此重複利用不會有風險</Line>
</Caption>

---
hideInToc: true
layout: center
---

# Bootstrap

如何讓 mruby 的初始化成本降到最低？

<!--
    60µs reuse #eval（scripts/warm_start.rb）
    1KB pure mruby sandbox（scripts/scale.rb）
-->

---
hideInToc: true
layout: diagram
---

<Stage column>
  <Group>
    <Block name="boot" color="tamago">初始化</Block>
    <Stroke dir="right" :label="$clicks >= 1 ? '建置' : ''" :labels="['建置']" />
    <Block name="image" color="gunJyo">映像</Block>
  </Group>

  <Stroke dir="down" :label="$clicks >= 2 ? '每次呼叫' : ''" :labels="['每次呼叫']" :hidden="$clicks < 2" />

  <Group name="copies">
    <Block color="gunJyo" :hidden="$clicks < 2">副本</Block>
    <Block color="gunJyo" :hidden="$clicks < 2">副本</Block>
    <Block color="gunJyo" :hidden="$clicks < 2">副本</Block>
  </Group>

  <Focus :steps="['boot', 'image', null, 'copies']" />
</Stage>

<Caption>
  <Line>我們每次都需要 mrb_open 初始化 mruby 虛擬機器</Line>
  <Line>但是初始化的流程完全一樣，把初始化後的記憶體形狀保存起來</Line>
  <Line>每次呼叫都使用相同的記憶體副本</Line>
  <Line>如果沒有運行任何腳本，就共用記憶體，每個 Sandbox 成本只有 1KB</Line>
</Caption>

---
hideInToc: true
layout: diagram
---

<Bars log axis-start="1µs" axis-end="1s" :steps="[null, 'e2b', 'kobako', 'monty']">
  <Bar name="lambda" :value="259" text="259ms" via="microVM">Lambda</Bar>
  <Bar name="docker" :value="220" text="220ms" via="Container">Docker</Bar>
  <Bar name="e2b" :value="200" text="200ms" via="microVM">E2B</Bar>
  <Bar name="kobako" :value="0.060" text="60µs" via="Wasm">kobako</Bar>
  <Bar name="monty" :value="0.026" text="26µs" via="Interpreter">Monty</Bar>
</Bars>

<Caption>
  <Line>在隔離環境跑一段程式碼的回應時間</Line>
  <Line>遠端呼叫還需要額外的網路成本</Line>
  <Line>Kobako 在同一個行程內，只需要運行的時間</Line>
  <Line>Python 生態的 Monty 連虛擬機器都不啟動，還可以更快</Line>
</Caption>

<!--
    自測（scripts/docker.rb, monty.py, untrusted_run.rb）
    無法測量由官網資料確認
-->

---
hideInToc: true
layout: diagram
---

<Map2D
  x-start="慢"
  x-end="快"
  y-start="受限"
  y-end="完整"
  :steps="[null, 'kobako']"
>
  <Point name="docker" :x="9" :y="90">Docker</Point>
  <Point name="e2b" :x="9" :y="78">E2B</Point>
  <Point name="lambda" :x="8" :y="66">Lambda</Point>
  <Point name="cloudflare" :x="58" :y="24">Cloudflare</Point>
  <Point name="kobako" :x="67" :y="36" tone="gunJyo">kobako</Point>
  <Point name="monty" :x="92" :y="12">Monty</Point>
</Map2D>

<Caption>
  <Line>所有技術都是在不同維度選擇選擇</Line>
  <Line>Kobako 選擇受到更多限制，換取更快的速度</Line>
</Caption>

<!--
    自測（scripts/workloads.rb, scripts/monty.py）
    座標計算（ruby scripts/map2d_points.rb）
-->

---
hideInToc: true
layout: diagram
---

<Map2D
  x-start="慢"
  x-end="快"
  y-start="鬆"
  y-end="緊"
  :steps="[null, 'kobako', 'monty']"
>
  <Point name="docker" :x="9" :y="21">Docker</Point>
  <Point name="e2b" :x="9" :y="78">E2B</Point>
  <Point name="lambda" :x="8" :y="90">Lambda</Point>
  <Point name="cloudflare" :x="58" :y="26">Cloudflare</Point>
  <Point name="kobako" :x="67" :y="38" tone="gunJyo">kobako</Point>
  <Point name="monty" :x="92" :y="12">Monty</Point>
</Map2D>

<Caption>
  <Line>隔離的邊界有多嚴格</Line>
  <Line>Kobako 是記憶體隔離，選擇用限制安全邊界的方式處理</Line>
  <Line>Monty 更快，但也犧牲掉一些隔離的保護</Line>
</Caption>

<!--
    座標使用腳本（ruby scripts/map2d_points.rb）X 軸保持不變
    隔離區分方式：記憶體邊界、OS 級隔離、預設拒絕、資源上限、敢不敢跑不受信任碼、攻擊面
-->

---
hideInToc: true
layout: diagram
---

<Stage>
  <Block color="gray">Monty</Block>
  <Block name="cloudflare" color="gunJyo">Cloudflare</Block>
  <Block name="kobako" color="gunJyo">kobako</Block>

  <Focus :steps="['', ['cloudflare', 'kobako']]" />
</Stage>

<Axis start="只能傳資料" end="可以傳物件" />

<Caption>
  <Line>原生的物件互動能力影響開發體驗</Line>
  <Line>Kobako 和 Cloudfalre 都提供呼叫遠端物件的機制</Line>
</Caption>

<!--
    Kobako 這邊比較寬鬆一點，但是 Cloudflare 也有提供類似的能力，Monty 只能傳資料
-->

---
hideInToc: true
layout: statement
---

```ruby {all|1-3|5|8-9}
class UserRepo
  def active = User.where(active: true)
end

sandbox.bind("Repo::User", UserRepo.new)

sandbox.eval(<<~RUBY).value
  Repo::User.active.order(:created_at).limit(10)
            .pluck(:name)
RUBY
```

---
hideInToc: true
layout: diagram
---

<!--
    量測（scripts/roundtrip.rb）。
-->

<Bars :steps="[null, 'sandbox', 'rails', null]">
  <Bar :value="4.2" text="4.2µs">Sandbox.new</Bar>
  <Bar :value="33" text="33µs">Thread.new + join</Bar>
  <Bar :value="60" text="60µs">User.first</Bar>
  <Bar :value="74" text="74µs">Sandbox#eval</Bar>
  <Bar name="rails" :value="76" text="76µs">User.first.to_json</Bar>
  <Bar name="sandbox" :value="80" text="80µs">Sandbox.new + eval</Bar>
</Bars>

<Caption>
  <Line>一次操作大概有多快，影響能不能大量使用</Line>
  <Line>跑一段腳本約 80µs 左右</Line>
  <Line>Rails 抓一筆資料轉成 JSON 約 76µs</Line>
  <Line>跟大部分 Rails 日常使用一樣的成本</Line>
  <Line>Kobako 傳輸使用 MessagePack 跟 #to_json 成本差不多</Line>
</Caption>

---
hideInToc: true
layout: center
---

# Scale

不需要考慮額外負擔，可以大量使用

<!--
    併發被問到再答：1/2/4/16 workers speedup = 1.00×（未釋放 GVL）。
    GVL 釋放實作在 feature/gvl-scheduling：compute-heavy ~7× 但 dispatch-heavy 0.52×，
    且 Handle id 每次 invocation 從 1 重編號會跨 thread 誤投——缺的是 per-invocation 身分。
-->


---
hideInToc: true
layout: diagram
---

<!--
    基於 scripts/scale.rb 測試（1000 個 Sandbox 的 RSS 差值）
-->

<Bars :steps="[null, 'process', 'sandboxes', null]">
  <Bar name="process" :value="29" text="29MB" via="單純啟動">Ruby 行程</Bar>
  <Bar name="sandboxes" :value="3.9" text="3.9MB" via="各跑一次">Kobako × 1000</Bar>
</Bars>

<Caption>
  <Line>同時跑 1,000 個 Kobako 沙盒也沒有負擔</Line>
  <Line>Ruby 本身約 29MB 啟動就需要支付相應的成本</Line>
  <Line>透過 CoW 啟動只需要副本，mruby 記憶體消耗本身就少，每個只要 4KB</Line>
  <Line>用 mruby 運行速度稍慢一點，換來可以在單節點大量使用</Line>
</Caption>

---
hideInToc: true
layout: statement
---

```ruby {all|1|2|4-5}
sandbox = Kobako::Sandbox.new
sandbox.bind("Repo::User")   # 宣告名字，物件每次呼叫才給

sandbox.eval(src) { |ctx| ctx.bind("Repo::User", alice_repo) }
sandbox.eval(src) { |ctx| ctx.bind("Repo::User", bob_repo) }
```

---
layout: section
---

# Isolation

比起複雜的安全檢查，直接隔離限制能力更簡單

---
hideInToc: true
layout: statement
---

```ruby {all|1-4|7|8-9|10-11}
sandbox = Kobako::Sandbox.new(
  timeout: 5.0, # 5s
  memory_limit: 10 * 1024 * 1024 # 10MB
)

begin
  sandbox.eval(llm_generated_code)
rescue Kobako::TrapError
  # 超過限制就放棄
rescue Kobako::SandboxError => e
  logger.warn(e.execution.stderr)
end
```

---
hideInToc: true
layout: center
---

# Bindings

開放綁定物件，讓擴充變簡單

---
hideInToc: true
layout: statement
---

```ruby {all|1-3|5|7|8}
class ThemeReader
  def color = AppConfig.theme.color
end

sandbox.bind("Cfg::Settings", ThemeReader.new)

sandbox.eval('Cfg::Settings.color').value  # => "#3366ff"
sandbox.eval('Cfg::Settings.secret_key')   # => NoMethodError
```

---
hideInToc: true
layout: center
---

# For AI and Others

這些特性都很適合在 AI 時代被 AI 使用，也能大大拖展可開發的應用類型

---
hideInToc: true
layout: center
---

# More Features

Kobako 還有不透明物件、跨語言支援等能力

---
layout: section
---

# Q&A
