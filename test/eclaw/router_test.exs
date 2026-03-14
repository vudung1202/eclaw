defmodule Eclaw.RouterTest do
  use ExUnit.Case, async: true

  alias Eclaw.Router

  @haiku_model "claude-haiku-4-5-20251001"

  describe "select_model/2 — simple prompts route to Haiku" do
    test "greeting routes to Haiku" do
      assert Router.select_model("hello") == @haiku_model
    end

    test "Vietnamese greeting routes to Haiku" do
      assert Router.select_model("xin chào") == @haiku_model
    end

    test "short question routes to Haiku" do
      assert Router.select_model("what is Elixir?") == @haiku_model
    end

    test "translate request routes to Haiku" do
      assert Router.select_model("translate this to English") == @haiku_model
    end

    test "format request routes to Haiku" do
      assert Router.select_model("format this JSON") == @haiku_model
    end

    test "simple yes/no routes to Haiku" do
      assert Router.select_model("yes") == @haiku_model
    end

    test "definition lookup routes to Haiku" do
      assert Router.select_model("define polymorphism") == @haiku_model
    end

    test "conversion request routes to Haiku" do
      assert Router.select_model("convert 5 miles to km") == @haiku_model
    end

    test "thank you routes to Haiku" do
      assert Router.select_model("thanks!") == @haiku_model
    end
  end

  describe "select_model/2 — complex prompts route to Sonnet" do
    test "analyze keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("analyze this codebase for performance issues") == default
    end

    test "debug keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("debug this failing test") == default
    end

    test "refactor keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("refactor the authentication module") == default
    end

    test "write code keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("write code for a REST API") == default
    end

    test "implement keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("implement a GenServer for caching") == default
    end

    test "fix keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("fix this bug in the parser") == default
    end

    test "explain keyword routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("explain the OTP supervision tree design") == default
    end

    test "long prompt without simple pattern routes to Sonnet" do
      default = Eclaw.Config.model()
      long_prompt = "I need help understanding the architecture of this system and how all the components interact with each other in production, including the supervision tree and message passing patterns"
      assert Router.select_model(long_prompt) == default
    end

    test "short prompt without simple pattern routes to Sonnet" do
      default = Eclaw.Config.model()
      assert Router.select_model("how does GenServer work internally?") == default
    end
  end

  describe "select_model/2 — explicit model override preserved" do
    test "returns explicit model as-is" do
      assert Router.select_model("hello", model: "custom-model-v1") == "custom-model-v1"
    end

    test "explicit model overrides even for complex prompts" do
      assert Router.select_model("analyze the codebase", model: "claude-haiku-4-5-20251001") == "claude-haiku-4-5-20251001"
    end
  end

  describe "select_model/2 — mid-loop iteration preserved" do
    test "iteration > 0 returns current_model" do
      assert Router.select_model("hello", iteration: 1, current_model: "my-model") == "my-model"
    end

    test "iteration > 0 without current_model returns Config default" do
      default = Eclaw.Config.model()
      assert Router.select_model("hello", iteration: 2) == default
    end

    test "iteration 0 still classifies normally" do
      assert Router.select_model("hello", iteration: 0) == @haiku_model
    end
  end
end
