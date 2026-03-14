defmodule EclawTest do
  use ExUnit.Case

  describe "public API facade" do
    test "module is loadable" do
      assert {:module, Eclaw} = Code.ensure_loaded(Eclaw)
    end

    test "exports chat/1" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :chat, 1)
    end

    test "exports stream/2" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :stream, 2)
    end

    test "exports reset/0" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :reset, 0)
    end

    test "exports session_chat/2" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :session_chat, 2)
    end

    test "exports remember/1 (with defaults)" do
      Code.ensure_loaded!(Eclaw)
      # remember/3 has 2 default args, so Elixir generates remember/1, /2, /3
      assert function_exported?(Eclaw, :remember, 1)
    end

    test "exports memories/0" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :memories, 0)
    end

    test "exports search_memory/1" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :search_memory, 1)
    end

    test "exports forget_all/0" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :forget_all, 0)
    end

    test "exports set_model/1" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :set_model, 1)
    end

    test "exports register_tool/1" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :register_tool, 1)
    end

    test "exports subscribe/0" do
      Code.ensure_loaded!(Eclaw)
      assert function_exported?(Eclaw, :subscribe, 0)
    end
  end
end
