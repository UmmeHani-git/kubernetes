##To keep continuous load for 5 minutes

#!/bin/bash

END=$((SECONDS + 300))   # 300 sec = 5 minutes

while [ $SECONDS -lt $END ]; do
    for i in {1..1000}; do
        curl -s -o /dev/null \
        http://a3d36bd399d15400f8e03cbaaa3f46c9-163245138.us-east-1.elb.amazonaws.com/ &
    done
    wait
done

echo "Load test completed after 5 minutes."
