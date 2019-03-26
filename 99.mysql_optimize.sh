#!/bin/bash

~/server/mysql/bin/mysql --login-path=root3306 -NBe "SHOW DATABASES;" | grep -vE -w 'Database|mysql|information_schema|coredns|mysql|performance_schema|sys' | while read database; do
    ~/server/mysql/bin/mysql --login-path=root3306 -NBe "SHOW TABLE STATUS;" $database | while read name engine version rowformat rows avgrowlength datalength maxdatalength indexlength datafree autoincrement createtime updatetime checktime collation checksum createoptions comment; do
        if [ "$datafree" -gt 0 ]; then
            fragmentation=$(echo "$datafree * 100 / $datalength" | bc -l)
            echo $fragmentation | grep -E '^\.' >/dev/null && fragmentation="0${fragmentation}"
            fragmentation=$(echo $fragmentation | sed 's/\(.[0-9]*\)$//g')
            printf "%-40s(%20s)\t is %04s" "$database.$name" $rows $fragmentation
            echo "% fragmented."
            if [ ${fragmentation} -lt 100 ]; then
                echo
                echo "    begin to optimize $database.$name";
                ~/server/mysql/bin/mysql --login-path=root3306 -NBe "OPTIMIZE TABLE $name;" "$database"
                echo
            fi
        fi
    done
done
