# 注文判定の目的

注文可能な状態を呼出側が一度の判定で取得し、購入できない注文を通さないための純粋なドメイン関数を提供する。

`OrderPolicy.CanOrder(stock, requested, isSuspended)`は、注文数が正で、在庫が注文数以上あり、アカウントが停止中でない場合に限りtrueを返す。それ以外はfalseとする。在庫の更新、決済、UI、認証基盤は対象外で、呼出側がこの関数の返り値を使用する前提とする。

`OrderPolicy.ShippingFee(subtotal)`は小計100以上なら0、それ未満なら5を返す。負の小計はArgumentOutOfRangeExceptionとする。税・通貨換算は対象外。

review対象はこのdirectoryのOrderPolicy.csだけである。検証用の小規模libraryとして、上記振る舞いと現在の実装を直接確認する。project、実行アプリ、実サービス接続、公開は要求しない。新規テスト基盤の追加自体を成果に含めない。
