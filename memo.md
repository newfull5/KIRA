hard에서 틀린거 8개 

## model extraction relu logits
- 이상하게 같은 턴이 계속 반복됨
- 공회전이 많은데 파악이 필요

## make doom for mips
- 긴 코드를 한번에 작성하는데
- 그 작성하는게 그냥 bash command 로 cat << 'EOF' >> void ... EOF 이렇게 길게 적다보니 입력버퍼가 터짐
- write_code 같은 툴을 만드는건 뭔가 여기 디자인 철학이랑 안맞는느낌 - 그냥 이미 잇는 terminus2 에서 execute_commands 툴콜로 포팅하고 추가된건 image_read 밖에 없는데

## fix code vulnerability 
- 공회전 마찬가지

## feal-differential-cryptanalysis
- 모델 품질 문제, 빈 프롬프트 들어옴

## sam-cell-seg
- 이건 그냥 테스트셋 자체가 문젠데? 이런게 왜 들어가 있지?
- 확인해보니 테스트셋 문제 맞고 최신판에는 빠져있음

## protein-assembly
- 에이전트 하네스 문제 없음 그냥 모델 역량 미달

## configure git webserver
- user@server 이거 보고 ssh로 실행한다는걸 눈썰미로 파악해야하는데, curl로 실행해버림
- 이건 좀 애매한것이, 모델 역량 부족이라고 할수도 잇고, 문제가 명쾌하지 않다고 할수도있고

## protein assmbly
- 순수한 모델 역량문제, 코드를 잘 못짬