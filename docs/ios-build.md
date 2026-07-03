# Build iOS do RapidHub Mobile

Como o app é Flutter e a máquina de desenvolvimento é Windows, o build iOS roda
num runner **macOS** do GitHub Actions — workflow em
[`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml).

> ⚠️ **Pré-requisito de conta:** o Actions só roda com a conta do GitHub dona do
> repo **sem bloqueio de faturamento**. Se um run falhar com
> *"account is locked due to a billing issue"*, regularize em
> <https://github.com/settings/billing> antes de tentar de novo.

Bundle ID do app: **`com.rapidhub.mobile`**.

---

## Modo 1 — `unsigned` (grátis, sem conta Apple paga)

Gera um `.ipa` **não assinado**. Não vai para App Store/TestFlight, mas pode ser
instalado em iPhone via sideload (a ferramenta re-assina com um Apple ID grátis).

### Gerar

```bash
gh workflow run ios-release.yml --ref main -f mode=unsigned
# ou: aba Actions → "iOS Release" → Run workflow → mode: unsigned
```

Ao terminar, baixe o artifact **`rapidhub-ios-ipa-unsigned`** (um `.zip` com o
`rapidhub-unsigned.ipa` dentro).

### Instalar no iPhone

Escolha **uma** ferramenta:

| Ferramenta | Plataforma | Observações |
|-----------|-----------|-------------|
| **Sideloadly** | Windows/Mac | Mais simples no Windows. Requer **iTunes + iCloud** (versões da Apple, não da Microsoft Store) para os drivers do dispositivo. |
| **AltStore / AltServer** | Windows/Mac | Re-assina sozinho a cada 7 dias enquanto o PC (AltServer) estiver na mesma Wi-Fi. |
| **TrollStore** | iPhone | Assinatura **permanente** (sem limite de 7 dias), mas só funciona em versões de iOS vulneráveis ao bug do CoreTrust. |

**Passo a passo (Sideloadly):**

1. Instale o [Sideloadly](https://sideloadly.io/) e o iTunes + iCloud da Apple.
2. Conecte o iPhone por cabo USB e confie no computador.
3. Abra o Sideloadly, arraste o `rapidhub-unsigned.ipa` para a janela.
4. Informe seu **Apple ID** (uma conta grátis serve) e clique em **Start**.
   O Sideloadly re-assina o app com um certificado de desenvolvimento gratuito e
   instala no aparelho.
5. No iPhone: **Ajustes → Geral → VPN e Gerenciamento de Dispositivos** →
   confie no seu perfil de desenvolvedor para poder abrir o app.

**Limitações do Apple ID gratuito:**

- O app **expira em 7 dias** — depois é só re-instalar/re-assinar (o AltStore faz
  isso automaticamente; no Sideloadly você repete o processo).
- No máximo **3 apps** sideloadados ao mesmo tempo por Apple ID.

---

## Modo 2 — `signed` (TestFlight / App Store)

Gera um `.ipa` **assinado** e, opcionalmente, faz upload para o TestFlight.
Requer **Apple Developer Program** (US$ 99/ano) e o cadastro dos secrets abaixo.

### Secrets a cadastrar

`Settings → Secrets and variables → Actions → New repository secret`
(ou `gh secret set NOME < arquivo`):

**Obrigatórios:**

| Secret | O que é / onde obter |
|--------|----------------------|
| `BUILD_CERTIFICATE_BASE64` | Certificado **Apple Distribution** exportado como `.p12`, em base64. |
| `P12_PASSWORD` | Senha definida ao exportar o `.p12`. |
| `BUILD_PROVISION_PROFILE_BASE64` | Provisioning profile **App Store** do `com.rapidhub.mobile` (`.mobileprovision`), em base64. |
| `PROVISIONING_PROFILE_NAME` | Nome exato do provisioning profile (como aparece no portal Apple). |
| `APPLE_TEAM_ID` | Team ID de 10 caracteres — Apple Developer → **Membership**. |
| `IOS_BUNDLE_ID` | `com.rapidhub.mobile` |
| `KEYCHAIN_PASSWORD` | Qualquer senha aleatória (keychain temporário do runner). |

**Opcionais — upload automático ao TestFlight (App Store Connect API key):**

| Secret | Onde obter |
|--------|-----------|
| `ASC_KEY_ID` | App Store Connect → **Users and Access → Integrations → Keys** → cria a key → *Key ID*. |
| `ASC_ISSUER_ID` | Mesma tela → *Issuer ID*. |
| `ASC_KEY_BASE64` | O arquivo `AuthKey_XXXXX.p8` baixado, em base64. |

Se os três `ASC_*` **não** forem cadastrados, o build ainda gera o `.ipa` como
artifact; só pula a etapa de upload.

### Como preparar o certificado e o profile

No portal <https://developer.apple.com/account>:

1. **Identifiers** → registre o App ID `com.rapidhub.mobile`.
2. **Certificates** → crie um certificado **Apple Distribution**.
3. **Profiles** → crie um provisioning profile **App Store** para esse App ID +
   o certificado acima → baixe o `.mobileprovision`.

> 💡 **Sem um Mac**, exportar o `.p12` a partir do certificado é o passo chato
> (normalmente feito pelo Acesso às Chaves do macOS). Alternativas: usar
> `fastlane match`, gerar via `openssl` a partir da chave privada + `.cer`, ou —
> mais fácil — usar o **Codemagic**, que gerencia a assinatura para você sem Mac.
> Se preferir esse caminho, peça que eu gero um `codemagic.yaml`.

### Gerar em base64 (Windows PowerShell)

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\caminho\cert.p12")) | Set-Clipboard
```

Cadastrar via `gh` (a partir de um arquivo já em base64):

```bash
gh secret set BUILD_CERTIFICATE_BASE64 < cert.p12.b64.txt
```

### Gerar o build assinado

```bash
gh workflow run ios-release.yml --ref main -f mode=signed
# ou crie uma tag de versão → build assinado automático:
git tag v1.0.0 && git push origin v1.0.0
```

Artifact de saída: **`rapidhub-ios-ipa`** (`build/ios/ipa/*.ipa`).
