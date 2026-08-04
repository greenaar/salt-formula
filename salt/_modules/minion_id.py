#!/usr/bin/env python
'''
Helper functions for doing things.
Note(s):
- Name returns s/./_/ to prevent sls render errors.
'''
import re

def replace(minion_id):
    '''
    Returns s/./_/ to prevent sls render errors.
    >>> minion_id = minion_id.replace('prd-ns-01.core.domain.tld')
    prd-ns-01_core_domain_tld
    '''
    return minion_id.replace('.', '_')
