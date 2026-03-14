defmodule Eclaw.ToolsTest do
  use ExUnit.Case

  alias Eclaw.Tools

  # Use project directory for temp files (within safe path prefix)
  @test_tmp Path.join(File.cwd!(), "tmp/test_tools")

  setup do
    File.mkdir_p!(@test_tmp)

    on_exit(fn ->
      File.rm_rf!(@test_tmp)
    end)

    :ok
  end

  # ── read_file/1 ────────────────────────────────────────────────────

  describe "read_file/1" do
    test "reads an existing file" do
      path = Path.join(@test_tmp, "read_test_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "Hello from test file")

      result = Tools.read_file(path)
      assert result == "Hello from test file"
    end

    test "returns error for non-existent file" do
      path = Path.join(@test_tmp, "nonexistent_#{System.unique_integer([:positive])}.txt")
      result = Tools.read_file(path)
      assert result =~ "Error: File not found"
    end

    test "returns error for directory instead of file" do
      dir = Path.join(@test_tmp, "subdir_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)

      result = Tools.read_file(dir)
      assert result =~ "Error:"
      assert result =~ "directory" or result =~ "is a directory"
    end

    test "returns security error for forbidden paths" do
      result = Tools.read_file("/etc/shadow")
      assert result =~ "Security error"
    end
  end

  # ── list_directory/1 ───────────────────────────────────────────────

  describe "list_directory/1" do
    test "lists contents of a real directory" do
      dir = Path.join(@test_tmp, "ls_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "file_a.txt"), "a")
      File.write!(Path.join(dir, "file_b.txt"), "b")
      File.mkdir_p!(Path.join(dir, "subdir"))

      result = Tools.list_directory(dir)
      assert result =~ "file_a.txt"
      assert result =~ "file_b.txt"
      assert result =~ "subdir"
      assert result =~ "[dir]"
      assert result =~ "[file]"
    end

    test "returns error for non-existent directory" do
      path = Path.join(@test_tmp, "nodir_#{System.unique_integer([:positive])}")
      result = Tools.list_directory(path)
      assert result =~ "Error: Directory not found"
    end

    test "lists project root directory" do
      cwd = File.cwd!()
      result = Tools.list_directory(cwd)
      assert result =~ "mix.exs"
    end
  end

  # ── search_files/1 ────────────────────────────────────────────────

  describe "search_files/1" do
    test "finds matching content in files" do
      dir = Path.join(@test_tmp, "search_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "hello.txt"), "Hello World\nGoodbye World\n")
      File.write!(Path.join(dir, "other.txt"), "No match here\n")

      result = Tools.search_files(%{"pattern" => "Hello", "path" => dir})
      assert result =~ "hello.txt"
      assert result =~ "Hello World"
      refute result =~ "No match here"
    end

    test "returns no matches message when nothing found" do
      dir = Path.join(@test_tmp, "search_empty_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "empty.txt"), "nothing special\n")

      result = Tools.search_files(%{"pattern" => "zzzznotfound", "path" => dir})
      assert result =~ "No matches found"
    end

    test "returns error for invalid regex pattern" do
      dir = Path.join(@test_tmp, "search_regex_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)

      result = Tools.search_files(%{"pattern" => "[invalid", "path" => dir})
      assert result =~ "Error: Invalid regex"
    end

    test "blocks path traversal in glob patterns" do
      dir = Path.join(@test_tmp, "search_glob_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)

      result = Tools.search_files(%{"pattern" => "test", "path" => dir, "glob" => "../../etc/*"})
      assert result =~ "Security error"
    end
  end

  # ── web_fetch/1 — SSRF blocking ───────────────────────────────────

  describe "web_fetch/1" do
    test "blocks non-HTTP URLs" do
      result = Tools.web_fetch("ftp://example.com/file")
      assert result =~ "Error: URL must start with http"
    end

    test "blocks internal IP addresses (SSRF)" do
      result = Tools.web_fetch("http://127.0.0.1/admin")
      assert result =~ "Security error"

      result = Tools.web_fetch("http://192.168.1.1/router")
      assert result =~ "Security error"

      result = Tools.web_fetch("http://10.0.0.1/internal")
      assert result =~ "Security error"
    end

    test "blocks localhost (SSRF)" do
      result = Tools.web_fetch("http://localhost:8080/")
      assert result =~ "Security error"
    end

    test "blocks metadata endpoint (SSRF)" do
      result = Tools.web_fetch("http://169.254.169.254/latest/meta-data/")
      assert result =~ "Security error"
    end

    test "blocks .internal hostnames" do
      result = Tools.web_fetch("http://metadata.google.internal/")
      assert result =~ "Security error"
    end

    @tag :integration
    test "fetches a real public URL" do
      result = Tools.web_fetch("https://httpbin.org/get")
      assert is_binary(result)
      refute result =~ "Security error"
    end
  end

  # ── execute/3 dispatch ─────────────────────────────────────────────

  describe "execute/3" do
    test "dispatches read_file tool" do
      path = Path.join(@test_tmp, "dispatch_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "dispatch test")

      result = Tools.execute("read_file", %{"path" => path})
      assert result == "dispatch test"
    end

    test "dispatches list_directory tool" do
      cwd = File.cwd!()
      result = Tools.execute("list_directory", %{"path" => cwd})
      assert result =~ "mix.exs"
    end

    test "returns error for unknown tool" do
      result = Tools.execute("nonexistent_tool_xyz", %{})
      assert result =~ "Unknown tool" or result =~ "error" or result =~ "Error"
    end
  end

  # ── write_file ─────────────────────────────────────────────────────

  describe "write_file/2 via execute" do
    test "writes a file successfully" do
      path = Path.join(@test_tmp, "write_#{System.unique_integer([:positive])}.txt")

      result = Tools.execute("write_file", %{"path" => path, "content" => "written content"})
      assert result =~ "Successfully wrote"

      # Verify file contents
      assert File.read!(path) == "written content"
    end
  end
end
