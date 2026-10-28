#!/usr/bin/env bash
# 리눅스에서 iOS 배포 서명 파일을 준비하고 GitHub Secrets에 넣는 도우미.
# 비밀 파일은 저장소 밖(~/.shotsort-signing, ShotSort와 공용 배포 인증서)에 있습니다. 절대 커밋하지 마세요.
#
#   tools/signing.sh csr  "이메일" "이름"     # 1) 개인키 + 인증서 요청(CSR) 생성
#   tools/signing.sh p12  ~/Downloads/distribution.cer   # 2) Apple에서 받은 .cer → .p12
#   tools/signing.sh secrets <프로파일.mobileprovision> <AuthKey_XXXX.p8> <ASC_ISSUER_ID>
#                                            # 3) GitHub Secrets 등록 (gh CLI 필요)
set -euo pipefail

DIR="${SIGNING_DIR:-$HOME/.shotsort-signing}"
mkdir -p "$DIR"
chmod 700 "$DIR"

cmd="${1:-}"; shift || true

case "$cmd" in
  csr)
    email="${1:?이메일을 넣어 주세요}"; name="${2:?이름(영문)을 넣어 주세요}"
    if [ -f "$DIR/dist.key" ]; then
      echo "이미 $DIR/dist.key 가 있어요. 새로 만들려면 먼저 지우세요."; exit 1
    fi
    openssl genrsa -out "$DIR/dist.key" 2048
    chmod 600 "$DIR/dist.key"
    openssl req -new -key "$DIR/dist.key" -out "$DIR/dist.csr" \
      -subj "/emailAddress=${email}/CN=${name}/C=KR"
    echo
    echo "✅ 인증서 요청 파일: $DIR/dist.csr"
    echo "   developer.apple.com → Certificates → + → 'Apple Distribution' 에 이 파일을 올리고"
    echo "   받은 distribution.cer 로 다음을 실행하세요:  tools/signing.sh p12 <distribution.cer>"
    ;;

  p12)
    cer="${1:?Apple에서 받은 .cer 파일 경로}"
    [ -f "$DIR/dist.key" ] || { echo "$DIR/dist.key 가 없어요. csr 단계부터 하세요."; exit 1; }
    openssl x509 -in "$cer" -inform DER -out "$DIR/dist.pem" -outform PEM
    pass=$(openssl rand -hex 12)
    # -legacy: OpenSSL 3의 기본 암호화 방식은 macOS 키체인이 읽지 못하는 경우가 있어 호환 방식으로 묶습니다.
    if ! openssl pkcs12 -export -legacy -inkey "$DIR/dist.key" -in "$DIR/dist.pem" \
         -out "$DIR/dist.p12" -passout "pass:$pass" 2>/dev/null; then
      openssl pkcs12 -export -inkey "$DIR/dist.key" -in "$DIR/dist.pem" \
        -out "$DIR/dist.p12" -passout "pass:$pass" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
    fi
    echo -n "$pass" > "$DIR/dist.p12.password"
    chmod 600 "$DIR/dist.p12" "$DIR/dist.p12.password"
    subject=$(openssl x509 -in "$DIR/dist.pem" -noout -subject)
    echo "✅ $DIR/dist.p12 생성 ($subject)"
    echo "   팀 ID(OU)가 위 subject에 보입니다."
    ;;

  secrets)
    profile="${1:?.mobileprovision 경로}"; p8="${2:?AuthKey_XXXX.p8 경로}"; issuer="${3:?ASC Issuer ID}"
    command -v gh >/dev/null || { echo "gh CLI가 필요해요: https://cli.github.com"; exit 1; }
    [ -f "$DIR/dist.p12" ] || { echo "dist.p12 가 없어요. p12 단계부터 하세요."; exit 1; }

    # 프로파일 안의 이름·팀 ID를 직접 읽어 오타를 막습니다.
    plist=$(openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null)
    pname=$(python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["Name"])' <<<"$plist")
    team=$(python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["TeamIdentifier"][0])' <<<"$plist")
    appid=$(python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["Entitlements"]["application-identifier"])' <<<"$plist")
    keyid=$(basename "$p8" .p8); keyid="${keyid#AuthKey_}"

    echo "프로파일: $pname / 팀: $team / 앱: $appid / API 키: $keyid"
    read -r -p "이 값으로 현재 저장소 Secrets를 등록할까요? [y/N] " ok
    [ "$ok" = "y" ] || exit 1

    gh secret set TEAM_ID --body "$team"
    gh secret set PROFILE_NAME --body "$pname"
    base64 -w0 "$profile" | gh secret set PROFILE_BASE64
    base64 -w0 "$DIR/dist.p12" | gh secret set DIST_P12_BASE64
    gh secret set DIST_P12_PASSWORD < "$DIR/dist.p12.password"
    gh secret set ASC_KEY_ID --body "$keyid"
    gh secret set ASC_ISSUER_ID --body "$issuer"
    base64 -w0 "$p8" | gh secret set ASC_KEY_P8_BASE64
    echo "✅ Secrets 8개 등록 완료. GitHub → Actions → 'Release to TestFlight' → Run workflow"
    ;;

  *)
    sed -n '2,9p' "$0"; exit 1 ;;
esac
