defmodule Eclaw.Browser do
  @moduledoc """
  Browser automation tool using Playwright CLI or Chrome DevTools Protocol (CDP).

  Provides tools for:
  - Navigating to URLs and capturing page content
  - Taking screenshots
  - Clicking elements and filling forms
  - Extracting structured data from web pages

  Requires: `npx playwright install chromium` (one-time setup)

  ## Usage as a tool

  Register as a plugin tool:

      Eclaw.ToolRegistry.register(Eclaw.Browser)

  The agent can then use these tools:
  - `browser_navigate` — Open a URL and get page content
  - `browser_screenshot` — Take a screenshot of the current page
  - `browser_click` — Click an element by selector
  - `browser_type` — Type text into an input field
  - `browser_evaluate` — Execute JavaScript in the page context
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

  # ── Private: Playwright Script Builders ────────────────────────────

  defp build_navigate_script(url, wait_for) do
    wait_line = if wait_for, do: "await page.waitForSelector(#{js_string_literal(wait_for)});", else: ""

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

  # Common Playwright script wrapper — all scripts share this boilerplate.
  defp wrap_playwright_script(url, action_code) do
    navigate_line = if url, do: "await page.goto(#{js_string_literal(url)}, { waitUntil: 'networkidle', timeout: 30000 });", else: ""

    """
    const { chromium } = require('playwright');
    (async () => {
      const browser = await chromium.launch({ headless: true });
      const page = await browser.newPage();
      #{navigate_line}
      #{action_code}
      await browser.close();
    })();
    """
  end

  # ── Private: Script Execution ──────────────────────────────────────

  defp run_playwright_script(script) do
    # Write script to temp file and execute with Node.js
    script_path = Path.join(System.tmp_dir!(), "eclaw_pw_#{:erlang.unique_integer([:positive])}.js")
    File.write!(script_path, script)

    try do
      task =
        Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
          System.cmd("node", [script_path],
            stderr_to_stdout: true
          )
        end)

      case Task.yield(task, 45_000) || Task.shutdown(task) do
        {:ok, {output, 0}} ->
          {:ok, String.trim(output)}

        {:ok, {output, code}} ->
          {:error, "Playwright exited with code #{code}: #{String.slice(output, 0, 500)}"}

        {:exit, reason} ->
          {:error, "Playwright crashed: #{inspect(reason)}"}

        nil ->
          {:error, "Playwright timed out after 45s"}
      end
    after
      File.rm(script_path)
    end
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
