defmodule Eclaw.Browser do
  @moduledoc """
  Browser automation tool using Playwright with persistent session support.

  Provides tools for:
  - Navigating to URLs and capturing page content
  - Taking screenshots
  - Clicking elements and filling forms
  - Extracting structured data from web pages
  - Manual login via visible browser (cookies saved for future use)

  Requires: `npx playwright install chromium` (one-time setup)

  ## Persistent Sessions

  All browser tools share a persistent profile at `~/.eclaw/browser-profile/`.
  Use `browser_login` to open a visible browser window, login manually, and
  cookies will be saved for all subsequent headless `browser_*` calls.

  ## Usage as a tool

  Register as a plugin tool:

      Eclaw.ToolRegistry.register(Eclaw.Browser)
  """

  require Logger

  # ── Multi-tool plugin (registered via ToolRegistry.register/1) ────

  def name, do: "browser"

  def description, do: "Browser automation tools (navigate, screenshot, click, type, evaluate JS)"

  def tools do
    [
      %{
        "name" => "browser_navigate",
        "description" =>
          "Navigate to a URL and return the page text content. " <>
            "Useful for reading web pages that require JavaScript rendering.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "url" => %{"type" => "string", "description" => "The URL to navigate to"},
            "wait_for" => %{"type" => "string", "description" => "CSS selector to wait for before extracting content (optional)"}
          },
          "required" => ["url"]
        }
      },
      %{
        "name" => "browser_screenshot",
        "description" =>
          "Take a screenshot of a web page. Returns the file path to the saved screenshot.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "url" => %{"type" => "string", "description" => "URL to screenshot (or uses current page if empty)"},
            "selector" => %{"type" => "string", "description" => "CSS selector to screenshot a specific element (optional)"},
            "full_page" => %{"type" => "boolean", "description" => "Capture full scrollable page (default: false)"}
          },
          "required" => []
        }
      },
      %{
        "name" => "browser_click",
        "description" => "Click an element on a web page by CSS selector.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "url" => %{"type" => "string", "description" => "URL to navigate to before clicking"},
            "selector" => %{"type" => "string", "description" => "CSS selector of the element to click"}
          },
          "required" => ["url", "selector"]
        }
      },
      %{
        "name" => "browser_type",
        "description" => "Type text into an input field on a web page identified by CSS selector.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "url" => %{"type" => "string", "description" => "URL to navigate to before typing"},
            "selector" => %{"type" => "string", "description" => "CSS selector of the input element"},
            "text" => %{"type" => "string", "description" => "Text to type into the field"}
          },
          "required" => ["url", "selector", "text"]
        }
      },
      %{
        "name" => "browser_evaluate",
        "description" =>
          "Execute JavaScript code in the browser page context and return the result. " <>
            "Useful for extracting structured data, interacting with page APIs, or running complex selectors.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "script" => %{"type" => "string", "description" => "JavaScript code to execute in the browser"},
            "url" => %{"type" => "string", "description" => "URL to navigate to first (optional)"}
          },
          "required" => ["script"]
        }
      },
      %{
        "name" => "browser_compose",
        "description" =>
          "Run multiple browser actions in a SINGLE session (navigate → wait → type → click → etc). " <>
            "IMPORTANT: Use this instead of separate browser_type + browser_click calls, because each " <>
            "separate call opens a NEW browser and loses previous state. " <>
            "Steps run sequentially on the same page. " <>
            "Supported step actions: wait (for selector), type (fill input), click, press (key like Enter), evaluate (JS).",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "url" => %{"type" => "string", "description" => "URL to navigate to first"},
            "steps" => %{
              "type" => "array",
              "description" => "Ordered list of actions to perform",
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "action" => %{"type" => "string", "description" => "wait | type | click | press | evaluate"},
                  "selector" => %{"type" => "string", "description" => "CSS selector (for wait/type/click/press)"},
                  "text" => %{"type" => "string", "description" => "Text to type (for type action)"},
                  "key" => %{"type" => "string", "description" => "Key to press (for press action, e.g. Enter)"},
                  "script" => %{"type" => "string", "description" => "JS code (for evaluate action)"},
                  "timeout" => %{"type" => "number", "description" => "Timeout in ms (for wait, default 10000)"}
                },
                "required" => ["action"]
              }
            }
          },
          "required" => ["url", "steps"]
        }
      },
      %{
        "name" => "browser_login",
        "description" =>
          "Open a VISIBLE browser window for manual login. " <>
            "The user logs in manually — cookies are saved to a persistent profile. " <>
            "All subsequent browser_* tool calls will reuse this login session. " <>
            "Use this once per site (e.g. Facebook, Google, GitHub) before using other browser tools on authenticated pages. " <>
            "The browser window stays open for 2 minutes.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "url" => %{"type" => "string", "description" => "URL to open for login (e.g. https://www.messenger.com)"}
          },
          "required" => ["url"]
        }
      }
    ]
  end

  def execute("browser_navigate", %{"url" => url} = input) do
    with :ok <- validate_browser_url(url) do
      wait_for = Map.get(input, "wait_for")
      navigate(url, wait_for: wait_for)
    end
  end

  def execute("browser_screenshot", input) do
    url = Map.get(input, "url")

    with :ok <- validate_browser_url(url) do
      selector = Map.get(input, "selector")
      full_page = Map.get(input, "full_page", false)
      screenshot(url: url, selector: selector, full_page: full_page)
    end
  end

  def execute("browser_click", %{"url" => url, "selector" => selector}) do
    with :ok <- validate_browser_url(url) do
      run_playwright_action("click", %{url: url, selector: selector})
    end
  end

  def execute("browser_type", %{"url" => url, "selector" => selector, "text" => text}) do
    with :ok <- validate_browser_url(url) do
      run_playwright_action("type", %{url: url, selector: selector, text: text})
    end
  end

  def execute("browser_evaluate", %{"script" => script} = input) do
    url = Map.get(input, "url")

    with :ok <- validate_browser_url(url) do
      evaluate(script, url: url)
    end
  end

  def execute("browser_compose", %{"url" => url, "steps" => steps}) when is_list(steps) do
    Logger.info("[Browser] compose → #{url} (#{length(steps)} steps)")
    with :ok <- validate_browser_url(url) do
      compose(url, steps)
    end
  end

  def execute("browser_login", %{"url" => url}) do
    with :ok <- validate_browser_url(url) do
      login(url)
    end
  end

  def execute(tool_name, _input) do
    {:error, "Unknown browser tool: #{tool_name}"}
  end

  # ── Public API ─────────────────────────────────────────────────────

  @doc "Navigate to URL and extract page content."
  @spec navigate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def navigate(url, opts \\ []) do
    wait_for = Keyword.get(opts, :wait_for)

    script = build_navigate_script(url, wait_for)
    run_playwright_script(script)
  end

  @doc "Take a screenshot."
  @spec screenshot(keyword()) :: {:ok, String.t()} | {:error, term()}
  def screenshot(opts \\ []) do
    url = Keyword.get(opts, :url)
    selector = Keyword.get(opts, :selector)
    full_page = Keyword.get(opts, :full_page, false)

    output_path = Path.join(System.tmp_dir!(), "eclaw_screenshot_#{:erlang.unique_integer([:positive])}.png")

    script = build_screenshot_script(url, output_path, selector: selector, full_page: full_page)

    case run_playwright_script(script) do
      {:ok, _} -> {:ok, "Screenshot saved to: #{output_path}"}
      error -> error
    end
  end

  @doc "Execute JavaScript in browser context."
  @spec evaluate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def evaluate(script, opts \\ []) do
    url = Keyword.get(opts, :url)
    pw_script = build_evaluate_script(url, script)
    run_playwright_script(pw_script)
  end

  @doc "Run multiple actions in a single browser session."
  @spec compose(String.t(), list(map())) :: {:ok, String.t()} | {:error, term()}
  def compose(url, steps) do
    action_lines =
      steps
      |> Enum.map(&build_compose_step/1)
      |> Enum.join("\n      ")

    script = wrap_playwright_script(url, """
      // Wait for page to be interactive
      await page.waitForFunction(() => (document.body.innerText || '').trim().length > 10, { timeout: 10000 }).catch(() => {});

      // Debug: log current URL and page title
      console.log('PAGE_URL: ' + page.url());
      console.log('PAGE_TITLE: ' + await page.title());

      try {
        #{action_lines}
        // Wait for pending network requests (message send, form submit, etc.)
        await page.waitForTimeout(3000);
        console.log('COMPOSE_OK');
      } catch (stepErr) {
        // On step failure, capture page state for debugging
        console.log('STEP_ERROR: ' + stepErr.message);
        const html = await page.content();
        // Log available input-like elements for debugging
        const inputs = await page.evaluate(() => {
          const els = document.querySelectorAll('[contenteditable], [role="textbox"], textarea, input[type="text"], [aria-label]');
          return Array.from(els).slice(0, 10).map(el => {
            const tag = el.tagName.toLowerCase();
            const role = el.getAttribute('role') || '';
            const placeholder = el.getAttribute('aria-placeholder') || el.getAttribute('placeholder') || '';
            const label = el.getAttribute('aria-label') || '';
            const ce = el.getAttribute('contenteditable') || '';
            return `<${tag} role="${role}" placeholder="${placeholder}" aria-label="${label}" contenteditable="${ce}">`;
          });
        });
        console.log('AVAILABLE_INPUTS: ' + JSON.stringify(inputs));
      }

      // Return final page text
      const result = await page.evaluate(() => document.body.innerText);
      console.log(result.substring(0, 2000));
    """)

    run_playwright_script(script, 60_000)
  end

  defp build_compose_step(%{"action" => "wait"} = step) do
    selector = step["selector"] || "body"
    timeout = step["timeout"] || 10_000
    "await page.waitForSelector(#{js_string_literal(selector)}, { timeout: #{timeout} });"
  end

  defp build_compose_step(%{"action" => "type", "selector" => selector, "text" => text}) do
    # Click to focus + keyboard.type for contenteditable support (Messenger, etc.)
    """
    await page.click(#{js_string_literal(selector)}, { force: true, timeout: 10000 });
    await page.keyboard.type(#{js_string_literal(text)}, { delay: 30 });
    """
  end

  defp build_compose_step(%{"action" => "click", "selector" => selector}) do
    "await page.click(#{js_string_literal(selector)}, { force: true, timeout: 10000 });"
  end

  defp build_compose_step(%{"action" => "press", "key" => key} = step) do
    selector = step["selector"] || "body"
    "await page.press(#{js_string_literal(selector)}, #{js_string_literal(key)});"
  end

  defp build_compose_step(%{"action" => "evaluate", "script" => script}) do
    encoded = Base.encode64(script)
    """
    {
      const userScript = Buffer.from(#{js_string_literal(encoded)}, 'base64').toString('utf-8');
      const wrapped = '(() => {' + userScript + '})()';
      const evalResult = await page.evaluate(wrapped);
      if (evalResult) console.log('eval:', JSON.stringify(evalResult));
    }
    """
  end

  defp build_compose_step(%{"action" => action}) do
    "// Unknown action: #{action}"
  end

  @doc "Open a visible browser for manual login. Cookies are saved to persistent profile."
  @spec login(String.t()) :: {:ok, String.t()} | {:error, term()}
  def login(url) do
    profile_dir = browser_profile_dir()

    script = """
    const { chromium } = require('playwright');
    (async () => {
      const context = await chromium.launchPersistentContext(#{js_string_literal(profile_dir)}, {
        headless: false,
        viewport: { width: 1280, height: 800 }
      });
      const page = context.pages()[0] || await context.newPage();
      await page.goto(#{js_string_literal(url)}, { waitUntil: 'domcontentloaded', timeout: 30000 });
      console.log('Browser opened. Please login manually. Window will close in 2 minutes.');
      await page.waitForTimeout(120000);
      await context.close();
      console.log('Login session saved.');
    })();
    """

    run_playwright_script(script, 150_000)
  end

  # ── Private: Playwright Script Builders ────────────────────────────

  defp build_navigate_script(url, wait_for) do
    wait_line =
      if wait_for do
        "await page.waitForSelector(#{js_string_literal(wait_for)}, { timeout: 10000 });"
      else
        # Wait for SPA content to render (body has meaningful text)
        """
        await page.waitForFunction(() => (document.body.innerText || '').trim().length > 50, { timeout: 10000 }).catch(() => {});
        """
      end

    wrap_playwright_script(url, """
      #{wait_line}
      const content = await page.evaluate(() => document.body.innerText);
      console.log(content.substring(0, 10000));
    """)
  end

  defp build_screenshot_script(url, output_path, opts) do
    selector = Keyword.get(opts, :selector)
    full_page = Keyword.get(opts, :full_page, false)

    screenshot_target =
      if selector do
        "await page.locator(#{js_string_literal(selector)}).screenshot({ path: #{js_string_literal(output_path)} });"
      else
        "await page.screenshot({ path: #{js_string_literal(output_path)}, fullPage: #{full_page} });"
      end

    wrap_playwright_script(url, """
      #{screenshot_target}
      console.log('Screenshot saved');
    """)
  end

  defp build_evaluate_script(url, js_code) do
    # Base64-encode user script to prevent Node.js template injection.
    # Decoded at runtime and passed as a string to page.evaluate (browser sandbox).
    encoded = Base.encode64(js_code)

    wrap_playwright_script(url, """
      const userScript = Buffer.from(#{js_string_literal(encoded)}, 'base64').toString('utf-8');
      const result = await page.evaluate(userScript);
      console.log(JSON.stringify(result, null, 2));
    """)
  end

  # Common Playwright script wrapper — uses persistent Chromium profile for session reuse.
  # Login once via browser_login, then all subsequent calls reuse saved cookies.
  defp wrap_playwright_script(url, action_code) do
    profile_dir = browser_profile_dir()
    navigate_line = if url, do: "await page.goto(#{js_string_literal(url)}, { waitUntil: 'domcontentloaded', timeout: 30000 });", else: ""

    """
    const { chromium } = require('playwright');
    (async () => {
      const context = await chromium.launchPersistentContext(#{js_string_literal(profile_dir)}, { headless: true });
      const page = context.pages()[0] || await context.newPage();
      #{navigate_line}
      #{action_code}
      await context.close();
    })();
    """
  end

  # ── Private: Script Execution ──────────────────────────────────────

  defp run_playwright_script(script, timeout \\ 45_000) do
    # Write script to temp file and execute with Node.js
    script_path = Path.join(System.tmp_dir!(), "eclaw_pw_#{:erlang.unique_integer([:positive])}.js")
    File.write!(script_path, script)

    try do
      task =
        Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
          System.cmd(node_binary(), [script_path],
            stderr_to_stdout: true,
            env: [{"NODE_PATH", node_modules_path()}]
          )
        end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, 0}} ->
          {:ok, String.trim(output)}

        {:ok, {output, code}} ->
          {:error, "Playwright exited with code #{code}: #{String.slice(output, 0, 500)}"}

        {:exit, reason} ->
          {:error, "Playwright crashed: #{inspect(reason)}"}

        nil ->
          {:error, "Playwright timed out after #{div(timeout, 1000)}s"}
      end
    after
      File.rm(script_path)
    end
  end

  # Find a working node binary (NVM-aware).
  # Elixir VM doesn't load NVM, so PATH may point to an old homebrew node.
  defp node_binary do
    nvm_node = Path.expand("~/.nvm/versions/node")

    case File.ls(nvm_node) do
      {:ok, versions} when versions != [] ->
        latest = versions |> Enum.sort(:desc) |> List.first()
        path = Path.join([nvm_node, latest, "bin", "node"])
        if File.exists?(path), do: path, else: "node"

      _ ->
        "node"
    end
  end

  # Resolve NODE_PATH so temp scripts can find playwright.
  # Includes all possible locations joined by ":" — project, home, NVM global.
  defp node_modules_path do
    candidates = [
      Path.join(File.cwd!(), "node_modules"),
      Path.expand("~/node_modules"),
      Path.join([Path.dirname(Path.dirname(node_binary())), "lib", "node_modules"])
    ]

    candidates
    |> Enum.filter(&File.dir?/1)
    |> Enum.join(":")
  end

  defp browser_profile_dir do
    dir = Path.expand("~/.eclaw/browser-profile")
    File.mkdir_p!(dir)
    dir
  end

  defp run_playwright_action(action, params) do
    script = case action do
      "click" ->
        wrap_playwright_script(params.url, """
          await page.click(#{js_string_literal(params.selector)});
          console.log("Clicked: " + #{js_string_literal(params.selector)});
        """)

      "type" ->
        wrap_playwright_script(params.url, """
          await page.fill(#{js_string_literal(params.selector)}, #{js_string_literal(params.text)});
          console.log("Typed into: " + #{js_string_literal(params.selector)});
        """)

      _ ->
        {:error, "Unknown action: #{action}"}
    end

    case script do
      {:error, _} = err -> err
      script_text -> run_playwright_script(script_text)
    end
  end

  # Validate URL against SSRF — reuses Eclaw.Tools.ssrf_blocked? logic
  defp validate_browser_url(nil), do: :ok
  defp validate_browser_url(""), do: {:error, "Empty URL is not allowed"}

  defp validate_browser_url(url) do
    if Eclaw.Security.safe_url?(url) do
      :ok
    else
      Logger.warning("[Eclaw.Browser] SSRF blocked: #{url}")
      {:error, "Security error: Access to internal/private network addresses is blocked"}
    end
  end

  # Safely encode a value as a JavaScript string literal (double-quoted).
  # Uses JSON encoding which is a valid JS string literal — no template injection possible.
  defp js_string_literal(nil), do: ~s("")
  defp js_string_literal(str), do: Jason.encode!(str)
end
