# Purpose Review Runner

`purpose-review-runner`は、独立したpurpose reviewerを起動し、同じreviewer sessionを最大3roundまで維持するローカルCLIです。実装担当エージェントへレビュー工程を教えるのは[`$persistent-purpose-review`](../../apm-packages/persistent-purpose-review/README.md)です。両方必要です。RunnerはPCへOS userごとに一度導入します。

通常はRunnerコマンドを手で呼ぶ必要はありません。主経路はSkillが`start` / `status` / `continue`を扱います。このREADMEはインストール、設定、更新、troubleshootingの正本です。手動CLIは[Advanced usage](#advanced-usage)にあります。

このRunnerは0.3.0以上が必要です。過去runの継続は[compatibility note](../../docs/purpose-review-runner-compatibility.md)を参照してください。

## Install

配布の正本は[GitHub Releases](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases)です。通常は[最新Release](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest)を使います。現在の最新は[purpose-review-runner-v0.3.0](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/tag/purpose-review-runner-v0.3.0)です。

| OS | asset |
| --- | --- |
| Windows x64 | [purpose-review-runner-win-x64.zip](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest/download/purpose-review-runner-win-x64.zip) |
| Linux x64 | [purpose-review-runner-linux-x64.tar.gz](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest/download/purpose-review-runner-linux-x64.tar.gz) |

install pathの正本は定めません。次の例は、展開・PATH追加・config作成・確認までを同じ変数でつなぎます。別のdirectoryを使う場合は`$installDir` / `$install_dir`だけ置き換えてください。

archiveには実行ファイルと[config.example.json](config.example.json)が含まれます。**configはRunner binaryの隣には置きません。** 展開先のexampleをuser-levelの設定ディレクトリへコピーします。

assetをダウンロードしたdirectoryで、次を実行します。

### Windows

```powershell
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\purpose-review-runner'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Expand-Archive -Force .\purpose-review-runner-win-x64.zip -DestinationPath $installDir

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrEmpty($userPath)) { $userPath = '' }
if (($userPath -split ';') -notcontains $installDir) {
    $updatedPath = @($userPath, $installDir) | Where-Object { $_ }
    [Environment]::SetEnvironmentVariable('Path', ($updatedPath -join ';'), 'User')
}
$env:Path = "$installDir;$env:Path"

$configDir = Join-Path $env:APPDATA 'purpose-review-runner'
$configPath = Join-Path $configDir 'config.json'
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
Copy-Item (Join-Path $installDir 'config.example.json') $configPath

# Codexの現行例を使うなら、開いた内容を保存するだけでよい。Grok / Copilot なら下の構文例に置き換える。
notepad $configPath

purpose-review-runner version
```

新しいPowerShellを開いても`purpose-review-runner`が見つからない場合は、一度サインアウトするか、同じ`$installDir`をUser PATHへ追加したことを確認します。

### Linux

```bash
install_dir="$HOME/.local/bin/purpose-review-runner"
mkdir -p "$install_dir"
tar -xzf purpose-review-runner-linux-x64.tar.gz -C "$install_dir"

export PATH="$install_dir:$PATH"
# 以降のshellでも使う場合は、次の1行を ~/.profile または ~/.bashrc へ追加する
# export PATH="$HOME/.local/bin/purpose-review-runner:$PATH"

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/purpose-review-runner"
mkdir -p "$config_dir"
cp "$install_dir/config.example.json" "$config_dir/config.json"

# Codexの現行例を使うなら、開いた内容を保存するだけでよい。Grok / Copilot なら下の構文例に置き換える。
${EDITOR:-nano} "$config_dir/config.json"

purpose-review-runner version
```

stdoutの単一JSONで`protocolVersion`が`3`、`runnerVersion`が`0.3.0`以上であることを確認します。`~/.local/bin`がPATHにあっても、その下の専用directoryは自動では検索されません。

## Config

設定ファイルはbinaryの配置先とは別に、`Environment.SpecialFolder.ApplicationData`配下の`purpose-review-runner/config.json`です。初回のコピーと編集は上のInstall例が担当します。

| OS | 実際のpath |
| --- | --- |
| Windows | `%APPDATA%\purpose-review-runner\config.json` |
| Linux | `$XDG_CONFIG_HOME/purpose-review-runner/config.json`。未設定時は`~/.config/purpose-review-runner/config.json` |

Linuxのpathは.NETの`Environment.SpecialFolder.ApplicationData`に従います。Unixでは`$XDG_CONFIG_HOME`、未設定時は`$HOME/.config`です。stateは`Environment.SpecialFolder.LocalApplicationData`配下で、Windowsでは`%LOCALAPPDATA%\purpose-review-runner\`、Linuxでは`$XDG_DATA_HOME`または`~/.local/share/purpose-review-runner\`です。

### 設定項目

現行の配布例です。Codexを使う場合はこのまま使えます。

```json
{
  "schemaVersion": 1,
  "provider": "codex",
  "executable": "codex",
  "model": "gpt-5.6-terra",
  "reasoningEffort": "high",
  "profile": null
}
```

| 項目 | 意味 |
| --- | --- |
| `schemaVersion` | config形式のversion。現在は`1` |
| `provider` | reviewer実装。`codex`、`grok`、`copilot`のいずれか |
| `executable` | PATH上のコマンド名、または実行ファイルの絶対path |
| `model` | そのprovider CLIへ渡すモデル名 |
| `reasoningEffort` | `none`、`minimal`、`low`、`medium`、`high`、`xhigh`、`max` |
| `profile` | 任意。未使用なら`null`。Codexは`-p`、Grok / Copilotは`--agent`へ渡します |

provider CLI自身の認証が事前に必要です。RunnerはAPI keyやOAuth設定を代行しません。

`start`にはreview単位の`--model`や`--effort` overrideはありません。reviewerには変更禁止を指示しますが、OS-levelのread-only isolationではありません。実装方式とprovider差分は[technical reference](../../docs/purpose-review-runner-technical-reference.md)を参照してください。

### Providerごとの構文例

次の`model`名は構文例です。推奨モデルではありません。利用可能なモデルは各provider CLIの現行一覧を使ってください。

Codex:

```json
{
  "schemaVersion": 1,
  "provider": "codex",
  "executable": "codex",
  "model": "gpt-5.6-terra",
  "reasoningEffort": "high",
  "profile": null
}
```

Grok:

```json
{
  "schemaVersion": 1,
  "provider": "grok",
  "executable": "grok",
  "model": "grok-4.6",
  "reasoningEffort": "high",
  "profile": null
}
```

Copilot:

```json
{
  "schemaVersion": 1,
  "provider": "copilot",
  "executable": "copilot",
  "model": "gpt-5.6",
  "reasoningEffort": "high",
  "profile": null
}
```

## Update

| 対象 | 手順 |
| --- | --- |
| Runner | [最新Release](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest)のarchiveを、同じinstall directoryへ展開して既存ファイルを置き換える |
| Skill | 実行環境のuser-scopeで更新する。手順は[Persistent Purpose Review README](../../apm-packages/persistent-purpose-review/README.md)と[APMの資料](https://microsoft.github.io/apm/reference/cli/install/)を参照 |
| config / state | 通常はそのまま。作り直したり移行したりしない |

更新後は`purpose-review-runner version`でprotocolとversionを確認します。protocol移行などの特殊ケースは[compatibility note](../../docs/purpose-review-runner-compatibility.md)を参照してください。

## Troubleshooting

内部実装ではなく、症状から確認します。reviewはバックグラウンドworkerで実行されるため、長時間でも親CLIに依存しません。1 roundはprovider timeoutまで約10分かかることがあります。`RUNNING`が続くこと自体は障害ではありません。

| 症状 | 確認 | 対処 |
| --- | --- | --- |
| `purpose-review-runner`が見つからない | PATHと展開先。`Get-Command purpose-review-runner`または`command -v purpose-review-runner` | [Install](#install)のPATH追加を、展開に使った同じdirectoryでやり直す |
| `CONFIG_NOT_FOUND` | エラーメッセージのpath。binaryの隣を見ていないか | [Install](#install)のconfigコピーを、展開先の`config.example.json`からやり直す |
| `EXECUTABLE_NOT_FOUND` / provider CLIが見つからない | configの`executable`とPATH | provider CLIを導入し、コマンド名または絶対pathを設定する |
| provider側の認証切れ | 同じ`executable`を単体実行して認証状態を確認する | そのprovider CLI自身で再認証する。Runner側にsecretは書かない |
| `RUNNING`が長い | `status --run <run-id>`を繰り返す。新しいrunを作っていないか | 同じ`run-id`の`status`だけをやり直す。1 roundは約10分かかることがある |
| Runner versionが古い / protocol非互換 | `purpose-review-runner version` | [最新Release](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest)へ差し替える。`apm update`では直らない |
| `HUMAN_DECISION_REQUIRED` | `message`とfinding。目的やscopeの選択が必要か | 人手で判断する。automatic round 4や別reviewerへの切替はしない |

## Advanced usage

Skillが使えない場合や診断時だけ、次を手で実行します。通常利用者の主経路ではありません。公開fieldsとstateの詳細は[technical reference](../../docs/purpose-review-runner-technical-reference.md)を参照してください。

```powershell
purpose-review-runner start --repository C:\path\to\repo --context docs\goal-context.md --context C:\path\to\accepted-decisions.md
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id>
```

## 関連文書

| 文書 | 役割 |
| --- | --- |
| [Persistent Purpose Review README](../../apm-packages/persistent-purpose-review/README.md) | 利用者の入口とSkillの利用方法 |
| このREADME | Runnerのインストール、設定、update、troubleshooting |
| [Technical reference](../../docs/purpose-review-runner-technical-reference.md) | protocol、state、worker、provider adapter |
| [Compatibility](../../docs/purpose-review-runner-compatibility.md) | version履歴とv2/v3非互換 |
| [Maintainer reference](../../docs/purpose-review-runner-maintenance.md) | 開発・リリース・validation。buildとRelease手順はこちら |
