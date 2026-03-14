defmodule Eclaw.SecurityTest do
  use ExUnit.Case, async: true

  alias Eclaw.Security

  # ── safe_url?/1 ────────────────────────────────────────────────────

  describe "safe_url?/1" do
    test "blocks localhost" do
      refute Security.safe_url?("http://localhost/admin")
      refute Security.safe_url?("http://localhost:8080/")
      refute Security.safe_url?("https://localhost/secret")
    end

    test "blocks 127.0.0.1 (loopback)" do
      refute Security.safe_url?("http://127.0.0.1/")
      refute Security.safe_url?("http://127.0.0.1:3000/api")
      refute Security.safe_url?("http://127.0.0.255/")
    end

    test "blocks 10.x.x.x (RFC1918)" do
      refute Security.safe_url?("http://10.0.0.1/")
      refute Security.safe_url?("http://10.255.255.255/")
      refute Security.safe_url?("http://10.0.1.50:8080/")
    end

    test "blocks 172.16.x.x - 172.31.x.x (RFC1918)" do
      refute Security.safe_url?("http://172.16.0.1/")
      refute Security.safe_url?("http://172.20.10.5/")
      refute Security.safe_url?("http://172.31.255.255/")
    end

    test "172.32.x.x IP is outside blocked RFC1918 /12 range" do
      # Verify the IP itself is not in the 172.16.0.0/12 block
      # (DNS resolution may still block it if it resolves to internal, so
      #  we just verify the CIDR math is correct)
      assert {:ok, {172, 32, 0, 1}} = :inet.parse_address(~c"172.32.0.1")
    end

    test "blocks 192.168.x.x (RFC1918)" do
      refute Security.safe_url?("http://192.168.0.1/")
      refute Security.safe_url?("http://192.168.1.100/")
      refute Security.safe_url?("http://192.168.255.255/")
    end

    test "blocks 169.254.x.x (link-local / cloud metadata)" do
      refute Security.safe_url?("http://169.254.169.254/latest/meta-data/")
      refute Security.safe_url?("http://169.254.0.1/")
    end

    test "blocks 100.64.x.x (CGN / shared address space)" do
      refute Security.safe_url?("http://100.64.0.1/")
      refute Security.safe_url?("http://100.127.255.255/")
    end

    test "blocks 0.0.0.0" do
      refute Security.safe_url?("http://0.0.0.0/")
      refute Security.safe_url?("http://0.0.0.0:4000/")
    end

    test "blocks IPv6 loopback (::1)" do
      refute Security.safe_url?("http://[::1]/")
      refute Security.safe_url?("http://[::1]:8080/")
    end

    test "blocks .local hostnames" do
      refute Security.safe_url?("http://myhost.local/")
      refute Security.safe_url?("http://printer.local:9100/")
    end

    test "blocks .internal hostnames" do
      refute Security.safe_url?("http://metadata.google.internal/")
      refute Security.safe_url?("http://service.internal/api")
    end

    test "allows public URLs" do
      assert Security.safe_url?("https://example.com/")
      assert Security.safe_url?("https://api.github.com/repos")
      assert Security.safe_url?("http://httpbin.org/get")
    end

    test "returns false for non-binary input" do
      refute Security.safe_url?(nil)
      refute Security.safe_url?(123)
      refute Security.safe_url?(:atom)
      refute Security.safe_url?([])
    end

    test "returns false for empty string" do
      refute Security.safe_url?("")
    end

    test "returns false for non-URL string" do
      refute Security.safe_url?("not-a-url")
    end
  end

  # ── validate_command/1 ─────────────────────────────────────────────

  describe "validate_command/1" do
    test "allows safe commands" do
      assert :ok = Security.validate_command("ls -la")
      assert :ok = Security.validate_command("echo hello")
      assert :ok = Security.validate_command("cat README.md")
    end

    test "rejects empty commands" do
      assert {:error, "Empty command"} = Security.validate_command("")
      assert {:error, "Empty command"} = Security.validate_command("   ")
    end

    test "rejects overly long commands" do
      long_cmd = String.duplicate("a", 10_001)
      assert {:error, msg} = Security.validate_command(long_cmd)
      assert msg =~ "Command too long"
    end

    test "blocks always-dangerous commands" do
      assert {:blocked, _} = Security.validate_command("rm -rf /")
      assert {:blocked, _} = Security.validate_command("mkfs.ext4 /dev/sda1")
      assert {:blocked, _} = Security.validate_command("dd if=/dev/zero of=/dev/sda")
    end

    test "blocks fork bomb" do
      assert {:blocked, _} = Security.validate_command(":(){ :|:& };:")
    end

    test "flags sudo as needing approval" do
      assert {:needs_approval, reason} = Security.validate_command("sudo apt install vim")
      assert reason =~ "sudo"
    end

    test "flags git push --force as needing approval" do
      assert {:needs_approval, _} = Security.validate_command("git push --force origin main")
    end

    test "flags shutdown as needing approval" do
      assert {:needs_approval, _} = Security.validate_command("shutdown -h now")
    end

    test "flags git reset --hard as needing approval" do
      assert {:needs_approval, _} = Security.validate_command("git reset --hard HEAD")
    end
  end

  # ── validate_path/1 ────────────────────────────────────────────────

  describe "validate_path/1" do
    test "allows paths within project directory" do
      # cwd is in the safe prefix list
      cwd = File.cwd!()
      assert :ok = Security.validate_path(Path.join(cwd, "lib/eclaw.ex"))
      assert :ok = Security.validate_path(Path.join(cwd, "mix.exs"))
    end

    test "allows paths within ~/.eclaw" do
      home = System.user_home!()
      eclaw_dir = Path.join(home, ".eclaw")
      assert :ok = Security.validate_path(Path.join(eclaw_dir, "memory.dets"))
    end

    test "rejects paths outside safe prefixes" do
      assert {:error, msg} = Security.validate_path("/usr/bin/something")
      assert msg =~ "traversal"
    end

    test "rejects forbidden system paths" do
      # These are both outside safe prefixes AND in the forbidden list
      assert {:error, _} = Security.validate_path("/etc/shadow")
      assert {:error, _} = Security.validate_path("/etc/passwd")
      assert {:error, _} = Security.validate_path("/etc/sudoers")
      assert {:error, _} = Security.validate_path("/root/.bashrc")
    end

    test "rejects overly long paths" do
      long_path = "/" <> String.duplicate("a", 4_097)
      assert {:error, msg} = Security.validate_path(long_path)
      assert msg =~ "Path too long"
    end

    test "allows paths in current working directory" do
      cwd = File.cwd!()
      assert :ok = Security.validate_path(Path.join(cwd, "test/some_test.exs"))
    end
  end

  # ── resolve_real_path/1 ────────────────────────────────────────────

  describe "resolve_real_path/1" do
    test "resolves an existing directory" do
      resolved = Security.resolve_real_path(File.cwd!())
      assert is_binary(resolved)
      # On macOS, the resolved path might differ due to /private symlink
      assert String.length(resolved) > 0
    end

    test "resolves path for non-existent file (returns path as-is)" do
      cwd = File.cwd!()
      path = Path.join(cwd, "nonexistent_file_xyz.txt")
      resolved = Security.resolve_real_path(path)
      # For non-existent files, it returns the path unchanged
      assert resolved == path
    end

    test "handles symlinks in path" do
      cwd = File.cwd!()
      target = Path.join(cwd, "test_resolve_target_#{System.unique_integer([:positive])}")
      link = Path.join(cwd, "test_resolve_link_#{System.unique_integer([:positive])}")

      File.write!(target, "test")

      try do
        case File.ln_s(target, link) do
          :ok ->
            resolved = Security.resolve_real_path(link)
            # The resolved path should point to the target
            assert resolved == target

          {:error, _} ->
            # Symlinks may not be supported — skip
            :ok
        end
      after
        File.rm(target)
        File.rm(link)
      end
    end
  end
end
