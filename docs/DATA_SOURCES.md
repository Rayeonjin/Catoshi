# 데이터 출처와 공유 범위

확인일: **2026-09-08 (KST)**

Catoshi는 비상업적 개인 사용 전용 앱입니다. 로그인이나 개인 API Key 없이 접근 가능한 시장 데이터 인터페이스를 이용하지만, 접근 가능하다는 사실이 데이터의 가공·재배포 허락을 의미하지는 않습니다. Catoshi 소스·고양이 자산의 라이선스와 제3자 데이터의 이용 조건은 별개입니다.

## 현재 공유 기능

시세·시장·국내 거래소 카드는 **시장 수치와 계산 지표를 포함**하고 정보 카드는 앱을 소개합니다. Feed·Story·Square, 이미지/캡션 복사, PNG 저장, macOS 공유를 제공합니다. 출처·실제 관측 시점·생성 시각·추정 지표를 카드와 캡션에 표시하며, 오래된 입력은 상태를 알리고 자동 해석에서 제외합니다.

무료 소스 공개와 사용자 직접 빌드는 앱 배포·접근 방식입니다. 사용자의 Mac이 데이터를 직접 받는 것과 그 데이터를 이미지로 다시 게시하는 것은 다른 사용 방식이므로 제공자의 조건도 함께 살펴야 합니다. 이 차이가 모든 개인 공유의 금지를 뜻하는 것은 아닙니다. 확인된 고지는 구현하고, 적용 범위가 불명확한 부분은 아래처럼 별도 기록합니다. 프로젝트 링크는 GitHub와 Telegram이며 후원과 데이터 출처는 구분합니다.

## 제공자별 확인 결과

아래의 ‘미확인’은 금지라는 법률 판단도, 허용이라는 보증도 아닙니다. Catoshi의 실제 사용 방식에 적용할 명시적 근거가 아직 확보되지 않았다는 뜻입니다. **이번 변경으로 제3자의 허락을 새로 얻은 것은 아니며, 확인 실패를 금지 근거로 삼지 않습니다.**

| 제공자 | 실제 사용처 | 개인 화면 조회·앱 내 계산 | 생성 이미지·캡션으로 데이터 재공유 | 공식 확인 자료 |
| --- | --- | --- | --- | --- |
| Binance | BTC/USDT·ETH/BTC, 캔들, OI·Funding, 실시간 가격 | 공식 Spot/Futures API 사용. 공개 조회 문서는 확인했으나 Catoshi의 계산·배포 구조에 대한 포괄적 권한 확인은 아님 | 공개 조회 문서만으로 이미지 재공유 허락을 확정하지 않음. 공유 범위 추가 확인 | [공식 API 문서](https://developers.binance.com/en/docs/introduction), [Spot REST](https://developers.binance.com/en/docs/products/spot/rest-api) |
| Upbit | BTC/KRW·USDT/KRW, 캔들, KRW 거래대금, 김치프리미엄 입력값 | 개발자센터에 게시된 Open API 약관 제6조의 유상 프로그램 양도·배포 제한 확인. 공개 시세의 계산/이용 범위는 별도 확인 필요 | 계산된 김치프리미엄·거래대금 이미지의 구체적 적용 조건 추가 확인 | [Open API 약관 원문 링크](https://upbit.com/open_api_agreement), [약관 본문이 함께 게시된 공식 개발자센터](https://docs.upbit.com/kr/page/upbit_developer_sdk_license) |
| Bithumb | 24h KRW 거래대금·Activity Radar | 공식 Public API 문서는 확인. 현행 약관 페이지에서 본문을 추출하지 못했으므로 약관 검토 완료로 표시하지 않음 | 현행 재공유 조건 미확인. 본문 조회 실패가 금지를 의미하지 않음 | [공식 API 안내](https://content.bithumb.com/apidocs/intro.html), [현행 API 약관 페이지](https://www.bithumb.com/member_operation/info_agree?key=info_api) |
| Coinone | 24h KRW 거래대금·Activity Radar | API 약관 제5조는 시세 조회를 포함. 제9조의 무단 사용·변경 제한이 있어 집계·차분 계산과 공개 API 적용 범위 확인 필요 | 제6조 제1항 제4호의 데이터 타인 양도 제한은 확인. 개인 공유 이미지·가공 지표가 해당하는 범위는 추가 확인 | [API 약관, 2026-05-07 시행](https://coinone.co.kr/terms/api) |
| Korbit | 24h KRW 거래대금·Activity Radar | 공식 문서에서 Public 시세 API의 무인증 접근을 확인. 가공/소스 배포에 따른 데이터 권한은 별도 확인 필요 | 명시적 재공유 조건 미확인. 개인 이미지 공유의 적용 범위 추가 확인 | [공식 API 문서](https://docs.korbit.co.kr/) |
| GOPAX | 24h KRW 거래대금·Activity Radar | 공식 Public API의 티커·24h 통계 경로 확인. 가공/소스 배포에 따른 데이터 권한은 별도 확인 필요 | 명시적 재공유 조건 미확인. 개인 이미지 공유의 적용 범위 추가 확인 | [공식 REST API 문서](https://gopax.github.io/API/), [공식 저장소](https://github.com/gopax/GopaxAPI) |
| CoinGecko | BTC.D·USDT.D·TOTAL3* 및 변화량 입력값 | API 약관의 제한적 사용 조건과 별도 플랜/계약 조건 적용. 필수 출처 표시를 시장·정보 화면에 반영. TOTAL3* 등 가공·캐시 및 무키 접근 범위는 추가 확인 대상 | 필수 출처·사이트 주소를 시장 카드와 캡션에 반영. 가공값 이미지 공유의 구체적 허용 범위는 추가 확인 | [API 약관, 2025-09-05 버전](https://www.coingecko.com/en/api_terms), [공식 FAQ](https://www.coingecko.com/en/faq) |
| DeFiLlama | USDT+USDC 공급량·7일 변화 | 약관 제7조에 비상업적 개인 접근·이용 범위, 제8조에 공식 Public API 및 복제·수정 제한이 함께 있음. 집계·변화량 계산의 적용 범위 추가 확인 | 제8조의 허락 없는 데이터 재게시 제한은 확인. 카드의 계산·해석과 원 데이터 재게시의 적용 범위 추가 확인 | [이용약관, 2025-06-24 시행](https://defillama.com/terms) |
| Farside Investors | 미국 현물 BTC ETF 일간·5거래일 순유입 | 공개 HTML 표에서 조회. 페이지 공개와 자동 수집·합계 가공 허락은 별개이며 명시적 근거 미확인 | 명시적 재공유 조건 미확인. 개인 이미지 공유의 적용 범위 추가 확인 | [공식 BTC ETF 데이터 페이지](https://farside.co.uk/btc/) |

Upbit의 SDK 라이선스 자체를 Catoshi 코드에 적용한다는 뜻은 아닙니다. 해당 공식 페이지에 함께 게시된 **Open API 이용약관**을 확인했습니다. Bithumb의 과거 PDF는 현행 약관 검토를 대신하지 않습니다. Binance DEX·지역별 거래 약관도 Catoshi의 Spot/Futures 데이터 권한 근거로 대체하지 않습니다.

## CoinGecko 출처 표시

[**Powered by CoinGecko**](https://www.coingecko.com/)

CoinGecko API는 CoinGecko의 자산입니다. API 약관 제4조 제3항은 눈에 잘 띄는 출처 문구와 10 이상 글자 크기를 요구합니다. Catoshi는 시장 탭의 한눈에·상세 화면 공통 하단과 정보 탭에 12pt 클릭 가능한 문구를 표시하고, 시장 카드에 18px 출처·사이트 주소, 캡션에 전체 URL을 넣습니다. macOS 공유 항목에도 CoinGecko 링크를 포함합니다. 공식 FAQ의 사이트 링크 안내도 반영했습니다. [브랜드 가이드](https://brand.coingecko.com/resources/attribution-guide)는 별도 확인할 자료이며 이번 웹 조회에서는 본문을 불러오지 못했습니다.

PNG의 사이트 주소는 이미지 자체에서 클릭되는 링크가 아닙니다. 따라서 시장 카드를 게시할 때 생성된 캡션의 CoinGecko URL을 함께 사용하고, 출처·관측 시각을 잘라내지 않는 구성이 적절합니다. 출처 표시의 반영과 구체적 데이터 이용 범위 확인은 별개 항목입니다.

## 계산값과 데이터 품질

- 김치프리미엄·거래소 비중·Activity Radar는 제공자의 원본 지표가 아니라 Catoshi가 계산한 값입니다.
- TOTAL3*는 전체 시가총액에서 BTC·ETH를 뺀 계산값이며, 동일 이름을 쓰는 다른 서비스 지수와 일치한다고 보장하지 않습니다.
- 제공자의 시점·필드·호출 제한·이용 조건이 달라질 수 있습니다. 지연·누락·수신 실패가 발생할 수 있으며, 마지막 갱신 시각과 수신 상태를 함께 확인해야 합니다.
- Catoshi와 제공자는 앱의 시장 해석을 투자자문이나 매수·매도 권유로 제공하지 않습니다. CoinGecko를 비롯한 제공자의 데이터는 정확성·완전성·연속성을 보장하지 않으며, 제공자는 Catoshi의 자동 해석이나 사용자의 투자 판단을 승인하지 않습니다.

## 개인정보와 요청 경로

시장 데이터 요청은 사용자의 Mac에서 각 제공자로 직접 전송됩니다. 제공자는 요청 처리 과정에서 IP 주소 등 일반 접속 정보를 받을 수 있으며 자신의 개인정보처리방침을 적용합니다. Catoshi는 거래소 계정, API Key, 지갑 키를 요구하지 않고 별도 사용자 계정 서버나 시장 데이터 중계 서버를 운영하지 않습니다.

이 문서의 확인일 이후 조건은 달라질 수 있습니다. 제공자 추가·유료화·후원 방식 변경·데이터 공유 범위 확대 시, 적용 약관과 허락 범위를 다시 확인합니다.
